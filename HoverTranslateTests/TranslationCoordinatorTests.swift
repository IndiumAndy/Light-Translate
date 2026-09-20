import XCTest
@testable import HoverTranslate

@MainActor
final class TranslationCoordinatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 3_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// A throwaway saved-entries directory: no test may touch the user's real
    /// Application Support file.
    private func temporaryLearningStore() -> LearningStore {
        LearningStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("HoverTranslateTests-" + UUID().uuidString, isDirectory: true))
    }

    private func makeCoordinator(extractor: GatedExtractor,
                                 presenter: RecordingPresenter,
                                 settings: StubSettings,
                                 locator: StubLocator? = nil,
                                 now: (() -> Date)? = nil)
        -> TranslationCoordinator {
        TranslationCoordinator(extractor: extractor,
                               presenter: presenter,
                               locator: locator ?? StubLocator(pid: 4242, bundleID: "com.example.reader"),
                               settings: settings,
                               learning: temporaryLearningStore(),
                               scheduler: SilentScheduler(),
                               now: now ?? { self.t0 },
                               pointerLocation: { CGPoint(x: 10, y: 10) })
    }

    /// A coordinator with a fake translation provider. `apiKey` empty means
    /// "no key configured yet".
    private func makeTranslatingCoordinator(
        extractor: GatedExtractor,
        presenter: RecordingPresenter,
        settings: StubSettings,
        translator: FakeTranslator,
        apiKey: String = "sk-test-not-a-real-key",
        model: String = "test-model",
        cache: TranslationCache? = nil,
        senses: WordSenseProviding? = nil)
        -> TranslationCoordinator {
        let context = TranslationContext(
            service: translator,
            cache: cache,
            configuration: {
                TranslationConfiguration(provider: "deepseek",
                                         model: model,
                                         apiKey: apiKey,
                                         isConfigured: !apiKey.isEmpty)
            })
        return TranslationCoordinator(extractor: extractor,
                                      presenter: presenter,
                                      locator: StubLocator(pid: 4242, bundleID: "com.example.reader"),
                                      settings: settings,
                                      translation: context,
                                      senses: senses,
                                      learning: temporaryLearningStore(),
                                      scheduler: SilentScheduler(),
                                      now: { self.t0 },
                                      pointerLocation: { CGPoint(x: 10, y: 10) })
    }

    /// Lets the coordinator task observe a resumed (or thrown) extraction.
    /// Cooperative yielding only: no sleeping, no wall-clock dependency.
    private func drain() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// Waits for an asynchronous condition without sleeping.
    @discardableResult
    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    private func dwell(_ coordinator: TranslationCoordinator) {
        coordinator.optionStateChanged(right: true, left: false)
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0))
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.3))
    }

    func testSlowFirstResultCannotOverwriteSecond() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)

        // Move to another word while the first extraction is still in flight.
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.4))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.7))
        await extractor.waitForRequests(2)

        await extractor.complete(generation: 2, text: "Settings")
        await extractor.complete(generation: 1, text: "Open")
        await drain()

        XCTAssertEqual(presenter.presented.map(\.text), ["Settings"])
    }

    func testReleaseBeforeResultDismissesAndLateResultIsIgnored() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)

        coordinator.optionStateChanged(right: false, left: false)
        XCTAssertGreaterThanOrEqual(presenter.dismissCount, 1)

        await extractor.complete(generation: 1, text: "Open")
        await drain()
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    /// v0.5: every application is readable by default; only an application the
    /// user excluded in Settings is refused.
    func testAnExcludedApplicationIsNeverRead() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: ["com.example.reader"]))
        dwell(coordinator)
        for _ in 0..<200 { await Task.yield() }
        let requested = await extractor.requestCount
        XCTAssertEqual(requested, 0)
        XCTAssertEqual(coordinator.lastFailure, .appNotAllowed)
        XCTAssertEqual(ExtractionFailure.appNotAllowed.message,
                       "this application is excluded in Settings")
    }

    func testEveryApplicationIsReadWithoutAnExclusionList() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "charge")
        await drain()
        XCTAssertEqual(presenter.presented.map(\.text), ["charge"],
                       "no application has to be added before it can be read")
        XCTAssertNil(coordinator.lastFailure)
    }

    /// A window whose application cannot be attributed at all is still refused:
    /// it cannot be matched against the exclusions either.
    func testASourceWithoutABundleIdentifierIsRefused() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = TranslationCoordinator(
            extractor: extractor,
            presenter: presenter,
            locator: StubLocator(pid: 4242, bundleID: nil),
            settings: StubSettings(excludedBundleIDs: []),
            learning: temporaryLearningStore(),
            scheduler: SilentScheduler(),
            now: { self.t0 },
            pointerLocation: { CGPoint(x: 10, y: 10) })
        dwell(coordinator)
        for _ in 0..<200 { await Task.yield() }
        let requested = await extractor.requestCount
        XCTAssertEqual(requested, 0)
        XCTAssertEqual(coordinator.lastFailure, .unknownOwner)
    }

    func testDisabledSettingNeverExtracts() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [])
        settings.isEnabled = false
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter, settings: settings)
        dwell(coordinator)
        for _ in 0..<200 { await Task.yield() }
        let requested = await extractor.requestCount
        XCTAssertEqual(requested, 0)
    }

    func testPinnedCardIsNotOverwrittenByNewHover() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "Open")
        await drain()
        XCTAssertEqual(presenter.presented.map(\.text), ["Open"])

        coordinator.optionStateChanged(right: false, left: false)
        coordinator.pin()
        XCTAssertTrue(presenter.pinned)

        coordinator.optionStateChanged(right: true, left: false)
        coordinator.pointerMoved(to: CGPoint(x: 400, y: 400), at: at(5.0))
        coordinator.pointerMoved(to: CGPoint(x: 400, y: 400), at: at(5.4))
        for _ in 0..<200 { await Task.yield() }
        let requested = await extractor.requestCount
        XCTAssertEqual(requested, 1)
        XCTAssertEqual(presenter.presented.map(\.text), ["Open"])
    }

    func testFrozenCardClosesAfterTheFreezeWindow() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "Open")
        await drain()

        coordinator.optionStateChanged(right: false, left: false)
        XCTAssertTrue(presenter.buttonsVisible)
        XCTAssertTrue(presenter.interactive)
        XCTAssertEqual(presenter.dismissCount, 0)

        coordinator.tick(now: at(0.5))
        XCTAssertEqual(presenter.dismissCount, 0)
        coordinator.tick(now: at(2.0))
        XCTAssertGreaterThanOrEqual(presenter.dismissCount, 1)
    }

    func testPointerInsideTheCardPausesClosing() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        // Away from the hover point used by dwell(), so only the explicit
        // pointer move enters the card.
        presenter.cardFrame = CGRect(x: 600, y: 600, width: 320, height: 80)
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "Open")
        await drain()
        coordinator.optionStateChanged(right: false, left: false)

        coordinator.pointerMoved(to: CGPoint(x: 700, y: 640), at: at(0.2))
        coordinator.tick(now: at(30))
        XCTAssertEqual(presenter.dismissCount, 0)

        coordinator.pointerMoved(to: CGPoint(x: 900, y: 900), at: at(31))
        coordinator.tick(now: at(31.5))
        XCTAssertEqual(presenter.dismissCount, 0)
        coordinator.tick(now: at(31.7))
        XCTAssertGreaterThanOrEqual(presenter.dismissCount, 1)
    }

    func testExtractionFailureHidesCardAndRecordsReason() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.fail(generation: 1, error: .positionUnresolved)
        await drain()

        XCTAssertEqual(coordinator.lastFailure, .positionUnresolved)
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertGreaterThanOrEqual(presenter.dismissCount, 1)
    }

    // MARK: - v0.2 translation

    private func beginTranslating(extractor: GatedExtractor,
                                  presenter: RecordingPresenter,
                                  coordinator: TranslationCoordinator,
                                  word: String) async {
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: word)
        await drain()
    }

    func testSlowFirstTranslationCannotOverwriteSecond() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)
        await translator.complete(translation: "收费", matching: "charge")

        // A second, later hover must win even when its answer arrives first.
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await extractor.waitForRequests(2)
        await extractor.complete(generation: 2, text: "fee")
        await drain()
        await translator.waitForRequests(2)
        await translator.complete(translation: "费用", matching: "fee")
        await drain()
        await translator.complete(translation: "迟到的收费", matching: "charge")
        await drain()

        XCTAssertEqual(presenter.translations, ["费用"])
    }

    func testReleasingTheTriggerDropsALateTranslation() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)

        let startedBeforeRelease = presenter.translatingCount
        coordinator.optionStateChanged(right: false, left: false)
        await translator.complete(translation: "收费", matching: "charge")
        await drain()

        XCTAssertTrue(presenter.translations.isEmpty,
                      "a translation that lands after release is not shown (translatingCount=\(startedBeforeRelease), presented=\(presenter.presented.map(\.text)))")
        XCTAssertEqual(presenter.presented.map(\.text), ["charge"], "the original text stays on the card")
    }

    /// A selection that is already on screen and hovered becomes exactly one
    /// request, in selection mode, carrying the whole selection.
    func testAHoveredSelectionBecomesOneSelectionRequest() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        let sentence = "Charge the battery before the trip."

        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: sentence, scope: .selection)
        await translator.waitForRequests(1)

        XCTAssertEqual(presenter.presented.map(\.text), [sentence], "the card shows the whole selection")
        XCTAssertEqual(coordinator.lastScope, .selection)
        let modes = await translator.modes
        XCTAssertEqual(modes, [.selection], "a whole selection goes out in selection mode, never word mode")

        // Only a body that matches exactly is completed, so a mismatch fails this
        // wait instead of passing silently.
        await translator.complete(translation: "出行前给电池充电。", matching: sentence)
        let shown = await waitUntil { presenter.translations == ["出行前给电池充电。"] }
        XCTAssertTrue(shown, "the selection's translation reaches the card")
    }

    /// A single word brings its parts of speech and meanings with it.
    func testAHoveredWordCarriesItsMeaningsFromTheWordbook() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let provider = StubWordSenseProvider(entries: [
            "charge": WordEntry(word: "charge",
                                senses: [WordSense(partOfSpeech: "n.", glosses: ["费用", "指控"]),
                                         WordSense(partOfSpeech: "vt.", glosses: ["充电"])],
                                truncated: false)
        ])
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: FakeTranslator(),
                                                     senses: provider)

        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "charge")
        let delivered = await waitUntil { presenter.dictionaries.count == 1 }

        XCTAssertTrue(delivered, "the card has to receive the meanings")
        XCTAssertEqual(presenter.dictionaries.first?.senses.map(\.partOfSpeech), ["n.", "vt."])
        XCTAssertEqual(presenter.dictionaries.first?.senses.first?.glosses, ["费用", "指控"])
        let asked = await provider.asked
        XCTAssertEqual(asked, ["charge"], "the wordbook is asked about the word that was read")
    }

    /// A sentence is not a word: nothing is asked of the wordbook.
    func testASentenceIsNotLookedUpInTheWordbook() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let provider = StubWordSenseProvider(entries: [:])
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: FakeTranslator(),
                                                     senses: provider)

        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "Charge the battery.", scope: .sentence)
        await drain()

        XCTAssertTrue(presenter.dictionaries.isEmpty)
        let asked = await provider.asked
        XCTAssertTrue(asked.isEmpty, "a sentence has no dictionary entry to ask for")
    }

    func testCachedAnswerCostsNoSecondRequest() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let cache = TranslationCache()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     cache: cache)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)
        await translator.complete(translation: "收费", matching: "charge")
        await waitUntil { presenter.translations == ["收费"] }
        // The cache write is asynchronous; give it its own turn before asking
        // for a second, identical query.
        await waitUntil { await cache.count == 1 }

        // Same word, same context: the visible answer must not cost a request.
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.0))
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.4))
        await extractor.waitForRequests(2)
        await extractor.complete(generation: 2, text: "charge")
        await drain()

        let requests = await translator.requestCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(presenter.translations, ["收费", "收费"])
    }

    func testMissingKeyKeepsTheOriginalAndNamesTheFix() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     apiKey: "")
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")

        let requests = await translator.requestCount
        XCTAssertEqual(requests, 0, "no key means no network call")
        XCTAssertEqual(presenter.translationFailures, [.apiKeyMissing])
        XCTAssertEqual(presenter.presented.map(\.text), ["charge"], "the English stays readable")
    }

    func testTranslationFailureKeepsTheEnglishVisible() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)
        await translator.complete(failure: .rateLimited)
        await drain()

        XCTAssertEqual(presenter.translationFailures, [.rateLimited])
        XCTAssertTrue(presenter.translations.isEmpty)
        XCTAssertEqual(presenter.presented.map(\.text), ["charge"])
    }

    func testCopyIsOnlyEverTriggeredByTheUser() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: FakeTranslator())
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        XCTAssertEqual(presenter.copyCount, 0, "an automatic query never writes the clipboard")

        coordinator.copyDisplayedText()
        XCTAssertEqual(presenter.copyCount, 1)
    }

    func testManualRequestWorksWithoutAHover() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        coordinator.attachManualPresenter(presenter)
        coordinator.submitManualText("Open Settings")
        let reachedProvider = await waitUntil { await translator.requestCount == 1 }
        XCTAssertTrue(reachedProvider, "the manual request reaches the provider")
        await translator.complete(translation: "打开设置")
        await waitUntil { presenter.manualResults == ["打开设置"] }

        XCTAssertEqual(presenter.manualResults, ["打开设置"], "manualFailure=\(String(describing: presenter.manualFailure))")
        let extracted = await extractor.requestCount
        XCTAssertEqual(extracted, 0, "manual entry must not read the screen")
    }

    func testManualTextIsRefusedBeforeItIsSent() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        coordinator.attachManualPresenter(presenter)
        coordinator.submitManualText(String(repeating: "x", count: 4001))
        await drain()

        let requests = await translator.requestCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(presenter.manualFailure, .configuration)
    }

    // MARK: - v0.4 explanation and saved entries

    /// A coordinator that knows a saved-entries file and can vary its key, so
    /// "the key was deleted" is testable without touching the real Keychain.
    private func makeLearningCoordinator(extractor: GatedExtractor,
                                         presenter: RecordingPresenter,
                                         settings: StubSettings,
                                         translator: FakeTranslator,
                                         store: LearningStore,
                                         apiKey: @escaping () -> String,
                                         model: String = "test-model") -> TranslationCoordinator {
        let context = TranslationContext(
            service: translator,
            cache: nil,
            configuration: {
                let key = apiKey()
                return TranslationConfiguration(provider: "deepseek",
                                                model: model,
                                                apiKey: key,
                                                isConfigured: !key.isEmpty)
            })
        return TranslationCoordinator(extractor: extractor,
                                      presenter: presenter,
                                      locator: StubLocator(pid: 4242, bundleID: "com.example.reader"),
                                      settings: settings,
                                      translation: context,
                                      learning: store,
                                      scheduler: SilentScheduler(),
                                      now: { self.t0 },
                                      pointerLocation: { CGPoint(x: 10, y: 10) })
    }

    /// Brings the card up with the word shown and the trigger released, which is
    /// the only state in which Explain and Save are reachable.
    private func showReleasedCard(extractor: GatedExtractor,
                                  presenter: RecordingPresenter,
                                  coordinator: TranslationCoordinator,
                                  word: String = "charge",
                                  translator: FakeTranslator? = nil,
                                  translatedAs translation: String? = nil) async {
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: word)
        await drain()
        // A translation that lands after the key is released is dropped by
        // design, so it has to arrive while the gesture is still held.
        if let translator, let translation {
            await translator.waitForRequests(1)
            await translator.complete(translation: translation, matching: word)
            await waitUntil { presenter.translations.contains(translation) }
        }
        coordinator.optionStateChanged(right: false, left: false)
    }

    func testNothingIsExplainedWithoutAClick() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator)
        await translator.waitForRequests(1)

        let requests = await translator.requestCount
        let modes = await translator.modes
        XCTAssertEqual(requests, 1, "only the translation the hover started")
        XCTAssertEqual(modes, [.word])
        XCTAssertEqual(coordinator.explanationStarts, 0)

        coordinator.pin()
        XCTAssertEqual(coordinator.explanationStarts, 0, "pinning is not asking for an explanation")
    }

    func testExplainSendsASecondRequestInTheExplanationMode() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     model: "test-model")
        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator)
        await translator.waitForRequests(1)

        coordinator.explainDisplayedText()
        await translator.waitForRequests(2)
        let modes = await translator.modes
        XCTAssertEqual(modes, [.word, .explanation])
        let models = await translator.models
        XCTAssertEqual(models, ["test-model", "test-model"], "the explanation uses the configured model too")
        XCTAssertEqual(coordinator.explanationStarts, 1)
        XCTAssertEqual(presenter.explanationLoadingCount, 1)

        await translator.completeNewest(translation: "在这个语境里是收费")
        await waitUntil { presenter.explanations.count == 1 }
        XCTAssertEqual(presenter.explanations.first, "在这个语境里是收费")
        XCTAssertEqual(coordinator.lastExplanationText, "在这个语境里是收费")
    }

    func testExplainIsIgnoredWhileTheTriggerIsStillHeld() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator)
        dwell(coordinator)
        await extractor.waitForRequests(1)
        await extractor.complete(generation: 1, text: "charge")
        await drain()
        XCTAssertEqual(coordinator.cardPhase, .live)

        // The card has no buttons while the key is held, so this must be a no-op
        // even if something called it.
        coordinator.explainDisplayedText()
        await drain()
        let modes = await translator.modes
        XCTAssertEqual(modes, [.word], "nothing beyond the hover's own translation")
        XCTAssertEqual(coordinator.explanationStarts, 0)
        XCTAssertTrue(presenter.explanations.isEmpty)
    }

    func testExplainWithoutAKeyNeverReachesTheProvider() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     apiKey: "")
        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator)
        let before = await translator.requestCount
        coordinator.explainDisplayedText()
        await drain()

        let after = await translator.requestCount
        XCTAssertEqual(after, before)
        XCTAssertEqual(coordinator.explanationStarts, 0)
        XCTAssertEqual(presenter.explanationFailures, [.apiKeyMissing])
    }

    /// Deleting the key must stop the next explanation, not just the next
    /// translation.
    func testDeletingTheKeyStopsFurtherExplanations() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        var key = "sk-test-not-a-real-key"
        let coordinator = makeLearningCoordinator(extractor: extractor,
                                                 presenter: presenter,
                                                 settings: StubSettings(excludedBundleIDs: []),
                                                 translator: translator,
                                                 store: temporaryLearningStore(),
                                                 apiKey: { key })
        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator)
        coordinator.explainDisplayedText()
        await translator.waitForRequests(2)

        key = ""
        coordinator.explainDisplayedText()
        await drain()
        let requests = await translator.requestCount
        XCTAssertEqual(requests, 2, "no request after the key was removed")
        XCTAssertEqual(presenter.explanationFailures, [.apiKeyMissing])
    }

    func testAHoverNeverSavesAnythingUntilTheUserClicks() async throws {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let store = temporaryLearningStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let coordinator = makeLearningCoordinator(extractor: extractor,
                                                 presenter: presenter,
                                                 settings: StubSettings(excludedBundleIDs: []),
                                                 translator: translator,
                                                 store: store,
                                                 apiKey: { "sk-test-not-a-real-key" })
        var reloads = 0
        coordinator.didSaveEntry = { reloads += 1 }

        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator,
                               translator: translator, translatedAs: "收费")
        XCTAssertEqual(try store.all().count, 0, "a hover, and the translation it started, save nothing")

        coordinator.pin()
        XCTAssertEqual(try store.all().count, 0, "pinning saves nothing")

        coordinator.saveDisplayedText()
        let saved = try store.all()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.source, "charge")
        XCTAssertEqual(saved.first?.translation, "收费")
        XCTAssertEqual(reloads, 1, "the open saved-entries list is told to reload")
        XCTAssertEqual(presenter.notes.last, "saved to your saved entries")
    }

    func testSaveRefusesWhenThereIsNothingTranslatedYet() async throws {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let store = temporaryLearningStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let coordinator = makeLearningCoordinator(extractor: extractor,
                                                 presenter: presenter,
                                                 settings: StubSettings(excludedBundleIDs: []),
                                                 translator: translator,
                                                 store: store,
                                                 apiKey: { "sk-test-not-a-real-key" })
        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator)

        coordinator.saveDisplayedText()
        XCTAssertEqual(try store.all().count, 0)
        XCTAssertEqual(presenter.notes.last, "translate first — there is nothing to save yet")
    }

    /// A file the store cannot read is reported and left exactly as it is.
    func testASavedFileThatCannotBeReadIsNeverOverwritten() async throws {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let store = temporaryLearningStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let garbage = "{ not the saved list"
        try Data(garbage.utf8).write(to: store.fileURL)

        let coordinator = makeLearningCoordinator(extractor: extractor,
                                                 presenter: presenter,
                                                 settings: StubSettings(excludedBundleIDs: []),
                                                 translator: translator,
                                                 store: store,
                                                 apiKey: { "sk-test-not-a-real-key" })
        await showReleasedCard(extractor: extractor, presenter: presenter, coordinator: coordinator,
                               translator: translator, translatedAs: "收费")

        coordinator.saveDisplayedText()
        XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), garbage)
        XCTAssertEqual(presenter.notes.last,
                       "saved entries could not be read, so nothing was written; clear them in Settings first")
    }

    func testClearingTheCacheMakesTheNextQueryCostARequestAgain() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let cache = TranslationCache()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     cache: cache)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)
        await translator.complete(translation: "收费", matching: "charge")
        await waitUntil { await cache.count == 1 }

        let cleared = await coordinator.clearTranslationCache()
        XCTAssertEqual(cleared, 1)
        let remaining = await cache.count
        XCTAssertEqual(remaining, 0)

        // The same word in the same context must now reach the provider again.
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.0))
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.4))
        await extractor.waitForRequests(2)
        await extractor.complete(generation: 2, text: "charge")
        await drain()
        await translator.waitForRequests(2)
        let requests = await translator.requestCount
        XCTAssertEqual(requests, 2)
    }

    // MARK: - v0.3 OCR fallback

    /// A coordinator with the screenshot fallback enabled. The OCR extractor and
    /// the permission are both injected, so nothing here touches the screen.
    private func makeOCROrGingCoordinator(primary: GatedExtractor,
                                           ocr: TextExtracting,
                                           presenter: RecordingPresenter,
                                           settings: StubSettings,
                                           captureAuthorized: @escaping () -> Bool = { true },
                                           locator: SourceLocating? = nil,
                                           pointerLocation: @escaping () -> CGPoint = { CGPoint(x: 10, y: 10) },
                                           now: @escaping () -> Date) -> TranslationCoordinator {
        TranslationCoordinator(extractor: primary,
                               presenter: presenter,
                               locator: locator ?? StubLocator(pid: 4242, bundleID: "com.example.reader"),
                               settings: settings,
                               ocrFallback: ocr,
                               captureAuthorized: captureAuthorized,
                               learning: temporaryLearningStore(),
                               scheduler: SilentScheduler(),
                               now: now,
                               pointerLocation: pointerLocation)
    }

    private func startFailing(
        _ coordinator: TranslationCoordinator,
        primary: GatedExtractor,
        generation: UInt64,
        failure: ExtractionFailure
    ) async {
        await primary.waitForRequests(Int(generation))
        await primary.fail(generation: generation, error: failure)
        await drain()
    }

    func testTechnicalFailureUsesTheOCRFallbackWhenEveryPrerequisiteIsMet() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { self.t0 })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)

        let requests = await ocr.requestCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(coordinator.ocrStarts, 1)
        XCTAssertEqual(presenter.presented.map(\.source), [.ocr])
        XCTAssertEqual(presenter.presented.map(\.scope), [.sentence])
        XCTAssertEqual(coordinator.lastFailure, nil)
    }

    func testAPolicyRefusalNeverStartsACapture() async {
        for failure in [ExtractionFailure.blockedSensitive, .appNotAllowed,
                        .permissionDenied, .unknownOwner, .timeout] {
            let primary = GatedExtractor()
            let ocr = RecordingOCRExtractor()
            let presenter = RecordingPresenter()
            let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
            let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                       settings: settings, now: { self.t0 })
            dwell(coordinator)
            await startFailing(coordinator, primary: primary, generation: 1, failure: failure)

            let requests = await ocr.requestCount
            XCTAssertEqual(requests, 0, "\(failure) must never start a capture")
            XCTAssertEqual(coordinator.ocrStarts, 0)
            XCTAssertEqual(coordinator.lastFailure, failure)
        }
    }

    func testTheFallbackNeedsBothTheSwitchAndThePermission() async {
        for (enabled, authorized) in [(false, true), (true, false), (false, false)] {
            let primary = GatedExtractor()
            let ocr = RecordingOCRExtractor()
            let presenter = RecordingPresenter()
            let settings = StubSettings(excludedBundleIDs: [],
                                        isOCRFallbackEnabled: enabled)
            let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                       settings: settings,
                                                       captureAuthorized: { authorized },
                                                       now: { self.t0 })
            dwell(coordinator)
            await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)
            let requests = await ocr.requestCount
            XCTAssertEqual(requests, 0, "enabled=\(enabled) authorized=\(authorized)")
            XCTAssertEqual(coordinator.lastFailure, .notSupported)
        }
    }

    func testTheRateLimitSkipsASecondCaptureWithinTheInterval() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        var clock = t0
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { clock })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)
        var requests = await ocr.requestCount
        XCTAssertEqual(requests, 1)

        // A second failure 100 ms later is still inside the interval.
        clock = at(0.1)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)
        requests = await ocr.requestCount
        XCTAssertEqual(requests, 1, "a moving pointer is not continuous screen recording")
        XCTAssertEqual(coordinator.ocrStarts, 1)

        // Past the interval, the fallback is available again.
        clock = at(1.0)
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.4))
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.8))
        await startFailing(coordinator, primary: primary, generation: 3, failure: .notSupported)
        requests = await ocr.requestCount
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(coordinator.ocrStarts, 2)
    }

    // MARK: - R2: a rate limit is a wait, not a failure

    /// The regression: a query refused by the interval used to end the hover, so
    /// staying still never tried again. It now waits for the earliest moment and
    /// runs exactly one capture there.
    func testARateLimitedQueryIsRetriedOnceTheIntervalHasPassed() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        var clock = t0
        var pointer = CGPoint(x: 10, y: 10)
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings,
                                                   pointerLocation: { pointer },
                                                   now: { clock })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)
        var requests = await ocr.requestCount
        XCTAssertEqual(requests, 1)

        // A second query 100 ms later is inside the interval, so it waits.
        clock = at(0.1)
        pointer = CGPoint(x: 200, y: 200)
        coordinator.pointerMoved(to: pointer, at: at(0.5))
        coordinator.pointerMoved(to: pointer, at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)
        requests = await ocr.requestCount
        XCTAssertEqual(requests, 1, "the interval still holds")
        XCTAssertEqual(presenter.statuses, [OCRFallbackPolicy.waitingStatus],
                       "waiting is reported instead of being treated as a failure")
        XCTAssertNil(coordinator.lastFailure, "nothing failed yet")

        // The pointer has not moved: the ticker reaches the earliest moment and
        // the capture runs once, for the same request.
        clock = at(0.9)
        coordinator.tick(now: at(0.9))
        let retried = await waitUntil { await ocr.requestCount == 2 }
        XCTAssertTrue(retried, "the deferred capture runs once the interval has passed")
        XCTAssertEqual(coordinator.ocrStarts, 2)
        let shown = await waitUntil { presenter.presented.count == 2 }
        XCTAssertTrue(shown)
        XCTAssertEqual(presenter.presented.last?.source, .ocr)
        XCTAssertNil(coordinator.lastFailure)
    }

    func testADeferredCaptureNeverFollowsThePointerToANewPosition() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        var clock = t0
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { clock })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)

        clock = at(0.1)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)

        // The pointer moves on: the deferred capture dies with the position that
        // asked for it, even after its earliest moment has passed.
        clock = at(2.0)
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(2.1))
        coordinator.tick(now: at(2.5))
        let requests = await ocr.requestCount
        XCTAssertEqual(requests, 1, "no capture of whatever moved into the old position")
    }

    func testAPendingCaptureIsDroppedWhenTheTriggerIsReleased() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        var clock = t0
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { clock })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)

        clock = at(0.1)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)

        coordinator.optionStateChanged(right: false, left: false)
        clock = at(2.0)
        coordinator.tick(now: at(2.0))
        let requests = await ocr.requestCount
        XCTAssertEqual(requests, 1, "releasing the key ends the hover, including its wait")
    }

    func testAPendingCaptureIsDroppedWhenTheSourceIsNoLongerTheSameWindow() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        let locator = MutableStubLocator(source: SourceApp(pid: 4242, bundleID: "com.example.reader"))
        var clock = t0
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, locator: locator, now: { clock })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)

        clock = at(0.1)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)

        // Another application is under the pointer now: capturing the old window
        // would attribute one application's pixels to another.
        locator.source = SourceApp(pid: 9999, bundleID: "com.example.other")
        clock = at(2.0)
        coordinator.tick(now: at(2.0))
        let requests = await ocr.requestCount
        XCTAssertEqual(requests, 1)
    }

    func testAPendingCaptureIsDroppedWhenTheApplicationIsExcludedMeanwhile() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        var clock = t0
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { clock })
        dwell(coordinator)
        await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)

        clock = at(0.1)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)

        // The rule changes while the capture waits. Nothing invalidates the wait
        // for us here: the retry has to re-check the rule itself.
        settings.excludedBundleIDs = ["com.example.reader"]
        clock = at(2.0)
        coordinator.tick(now: at(2.0))
        let requests = await ocr.requestCount
        XCTAssertEqual(requests, 1, "an excluded application is not captured")
    }

    func testNoCaptureIsDeferredWithoutTheSwitchOrThePermission() async {
        for (enabled, authorized) in [(false, true), (true, false)] {
            let primary = GatedExtractor()
            let ocr = RecordingOCRExtractor()
            let presenter = RecordingPresenter()
            let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: enabled)
            var clock = t0
            let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                       settings: settings,
                                                       captureAuthorized: { authorized },
                                                       now: { clock })
            dwell(coordinator)
            await startFailing(coordinator, primary: primary, generation: 1, failure: .notSupported)
            clock = at(3.0)
            coordinator.tick(now: at(3.0))

            let requests = await ocr.requestCount
            XCTAssertEqual(requests, 0, "enabled=(enabled) authorized=(authorized)")
            XCTAssertEqual(presenter.statuses, [ExtractionFailure.notSupported.message],
                           "the refusal is stated once instead of showing nothing")
        }
    }

    func testADeferredCaptureNeverOverlapsACaptureThatIsStillRunning() async {
        let primary = GatedExtractor()
        let ocr = GatedExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        var clock = t0
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { clock })
        dwell(coordinator)
        await primary.waitForRequests(1)
        await primary.fail(generation: 1, error: .notSupported)
        await ocr.waitForRequests(1)

        clock = at(0.1)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: primary, generation: 2, failure: .notSupported)

        // The first capture has still not finished, so the interval passing must
        // not put a second one on the screen.
        clock = at(3.0)
        coordinator.tick(now: at(3.0))
        let requests = await ocr.requestCount
        XCTAssertEqual(requests, 1, "never two captures at once")
        XCTAssertEqual(coordinator.ocrStarts, 1)
    }

    // MARK: - R4: a failure is not silence

    func testAnUnreadableHoverStatesTheReasonInsteadOfShowingNothing() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor,
                                         presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await startFailing(coordinator, primary: extractor, generation: 1, failure: .positionUnresolved)

        XCTAssertEqual(presenter.statuses, [ExtractionFailure.positionUnresolved.message])
        XCTAssertTrue(presenter.presented.isEmpty, "a status is not a card")
        XCTAssertEqual(coordinator.lastFailure, .positionUnresolved)
    }

    func testTheSameStatusIsThrottledAndThenGoesAwayOnItsOwn() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        var clock = t0
        let coordinator = makeCoordinator(extractor: extractor,
                                         presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []),
                                         now: { clock })
        // A coordinator with no OCR fallback: every technical failure is final.
        dwell(coordinator)
        await startFailing(coordinator, primary: extractor, generation: 1, failure: .noText)
        XCTAssertEqual(presenter.statuses, [ExtractionFailure.noText.message])

        // The same reason half a second later is not repeated.
        clock = at(0.5)
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await startFailing(coordinator, primary: extractor, generation: 2, failure: .noText)
        XCTAssertEqual(presenter.statuses.count, 1)

        // A different reason is a different line. The pointer returns to the point
        // the coordinator samples, so the next tick has nothing to restart.
        clock = at(0.6)
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(1.0))
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(1.4))
        await startFailing(coordinator, primary: extractor, generation: 3, failure: .blockedSensitive)
        XCTAssertEqual(presenter.statuses.last, ExtractionFailure.blockedSensitive.message)

        // And it disappears on its own: one tick past its lifetime, with no key
        // press, no click and no pointer movement of any kind.
        let dismissalsBefore = presenter.statusDismissCount
        clock = at(3.0)
        coordinator.tick(now: at(3.0))
        XCTAssertEqual(presenter.statusDismissCount, dismissalsBefore + 1)
        XCTAssertEqual(coordinator.cardPhase, .hidden)
    }

    /// The OCR layer is the second one that can answer late. It shares the same
    /// generation gate as Accessibility and the network.
    func testASlowOCRResultCannotOverwriteANewerHover() async {
        let primary = GatedExtractor()
        let ocr = GatedExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { self.t0 })
        dwell(coordinator)
        await primary.waitForRequests(1)
        await primary.fail(generation: 1, error: .notSupported)
        await ocr.waitForRequests(1)

        // A newer hover resolves through Accessibility while the capture is still
        // being recognized.
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.5))
        coordinator.pointerMoved(to: CGPoint(x: 200, y: 200), at: at(0.9))
        await primary.waitForRequests(2)
        await primary.complete(generation: 2, text: "fee")
        await drain()
        await ocr.complete(generation: 1, text: "Image sentence from the old capture", scope: .sentence)
        await drain()

        XCTAssertEqual(presenter.presented.map(\.text), ["fee"],
                       "the late OCR answer must not revive the old card")
    }

    func testReleasingTheTriggerDropsALateOCRResult() async {
        let primary = GatedExtractor()
        let ocr = GatedExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { self.t0 })
        dwell(coordinator)
        await primary.waitForRequests(1)
        await primary.fail(generation: 1, error: .notSupported)
        await ocr.waitForRequests(1)

        coordinator.optionStateChanged(right: false, left: false)
        await ocr.complete(generation: 1, text: "Image sentence", scope: .sentence)
        await drain()
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    func testIdleCountersDoNotGrowWithoutATrigger() async {
        let primary = GatedExtractor()
        let ocr = RecordingOCRExtractor()
        let presenter = RecordingPresenter()
        let settings = StubSettings(excludedBundleIDs: [], isOCRFallbackEnabled: true)
        let coordinator = makeOCROrGingCoordinator(primary: primary, ocr: ocr, presenter: presenter,
                                                   settings: settings, now: { self.t0 })
        for _ in 0..<200 { await Task.yield() }
        let extracted = await primary.requestCount
        let captured = await ocr.requestCount
        XCTAssertEqual(extracted, 0)
        XCTAssertEqual(captured, 0)
        XCTAssertEqual(coordinator.translationStarts, 0)
        XCTAssertEqual(coordinator.ocrStarts, 0)
    }

    // MARK: - v0.3 sentence mode

    func testSwitchingToSentenceModeDropsTheWordRequest() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        let firstModes = await extractor.requestedModes
        XCTAssertEqual(firstModes, [.word])

        // Control goes down mid-gesture: the word request is already superseded.
        coordinator.optionStateChanged(right: true, left: false, control: true)
        await extractor.complete(generation: 1, text: "Open")
        await drain()
        XCTAssertTrue(presenter.presented.isEmpty, "the superseded word result never reaches the card")

        // The dwell restarts and the next request asks for a sentence.
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.4))
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.7))
        await extractor.waitForRequests(2)
        let sentenceMode = await extractor.mode(ofGeneration: 2)
        XCTAssertEqual(sentenceMode, .sentence)
        await extractor.complete(generation: 2, text: "Open Settings.", scope: .sentence)
        await drain()
        XCTAssertEqual(presenter.presented.map(\.text), ["Open Settings."])
        XCTAssertEqual(presenter.presented.map(\.scope), [.sentence])
    }

    func testReleasingControlDropsTheSentenceRequestAndReturnsToWord() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        coordinator.optionStateChanged(right: true, left: false, control: true)
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0))
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.3))
        await extractor.waitForRequests(1)
        let sentenceMode = await extractor.mode(ofGeneration: 1)
        XCTAssertEqual(sentenceMode, .sentence)

        coordinator.optionStateChanged(right: true, left: false, control: false)
        await extractor.complete(generation: 1, text: "Open Settings.", scope: .sentence)
        await drain()
        XCTAssertTrue(presenter.presented.isEmpty)

        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.4))
        coordinator.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.7))
        await extractor.waitForRequests(2)
        let wordMode = await extractor.mode(ofGeneration: 2)
        XCTAssertEqual(wordMode, .word)
    }

    func testExternalChangeInvalidatesOutstandingWork() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let coordinator = makeCoordinator(extractor: extractor, presenter: presenter,
                                         settings: StubSettings(excludedBundleIDs: []))
        dwell(coordinator)
        await extractor.waitForRequests(1)
        coordinator.externalChange()
        await extractor.complete(generation: 1, text: "Open")
        await drain()
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    // MARK: - R1: the selection entry reads the focused control

    /// A coordinator whose selection entry is entirely fake: no Accessibility,
    /// no running application and no clipboard are involved.
    private func makeSelectionCoordinator(presenter: RecordingPresenter,
                                          settings: StubSettings,
                                          reader: StubSelectionReader,
                                          translator: FakeTranslator = FakeTranslator(),
                                          bundleIdentifier: String? = "com.example.reader",
                                          apiKey: String = "sk-test-not-a-real-key",
                                          cache: TranslationCache? = nil) -> TranslationCoordinator {
        let context = TranslationContext(
            service: translator,
            cache: cache,
            configuration: {
                TranslationConfiguration(provider: "deepseek",
                                         model: "test-model",
                                         apiKey: apiKey,
                                         isConfigured: !apiKey.isEmpty)
            })
        let coordinator = TranslationCoordinator(extractor: GatedExtractor(),
                                                 presenter: presenter,
                                                 locator: StubLocator(pid: 4242, bundleID: "com.example.reader"),
                                                 settings: settings,
                                                 translation: context,
                                                 learning: temporaryLearningStore(),
                                                 selectionReader: reader,
                                                 bundleIdentifierForPID: { _ in bundleIdentifier },
                                                 scheduler: SilentScheduler(),
                                                 now: { self.t0 },
                                                 pointerLocation: { CGPoint(x: 10, y: 10) })
        coordinator.attachManualPresenter(presenter)
        return coordinator
    }

    func testSelectionFromAnExcludedApplicationIsNeverRead() async {
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: false))
        await reader.setText("Secret")
        let coordinator = makeSelectionCoordinator(
            presenter: presenter,
            settings: StubSettings(excludedBundleIDs: ["com.example.reader"]),
            reader: reader,
            translator: translator)

        coordinator.handleSelectionRequest()
        await drain()

        let focused = await reader.focusedCount
        let read = await reader.bodyReadCount
        let requests = await translator.requestCount
        XCTAssertEqual(focused, 1, "the source is resolved first")
        XCTAssertEqual(read, 0, "an excluded application must not have its selection read")
        XCTAssertEqual(requests, 0, "and nothing is sent for it")
        XCTAssertEqual(presenter.manualPrompts.count, 1)
        XCTAssertEqual(presenter.manualPrompts.first ?? nil, .appNotAllowed)
    }

    func testSelectionFromAnUnknownSourceIsRefusedBeforeTheBodyIsRead() async {
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: false))
        await reader.setText("Secret")
        let coordinator = makeSelectionCoordinator(presenter: presenter,
                                                   settings: StubSettings(excludedBundleIDs: []),
                                                   reader: reader,
                                                   translator: translator,
                                                   bundleIdentifier: nil)

        coordinator.handleSelectionRequest()
        await drain()

        let read = await reader.bodyReadCount
        let requests = await translator.requestCount
        XCTAssertEqual(read, 0, "a source with no bundle identifier cannot be attributed, so it is not read")
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(presenter.manualPrompts.first ?? nil, .unknownOwner)
    }

    func testSelectionFromASecureControlIsRefusedBeforeTheBodyIsRead() async {
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: true))
        await reader.setText("hunter2")
        let coordinator = makeSelectionCoordinator(presenter: presenter,
                                                   settings: StubSettings(excludedBundleIDs: []),
                                                   reader: reader,
                                                   translator: translator)

        coordinator.handleSelectionRequest()
        await drain()

        let read = await reader.bodyReadCount
        XCTAssertEqual(read, 0, "a protected control is never read, even on an explicit action")
        XCTAssertEqual(presenter.manualPrompts.first ?? nil, .blockedSensitive)
    }

    func testAnAllowedSelectionIsReadAndTranslated() async {
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: false))
        await reader.setText("Open Settings")
        let coordinator = makeSelectionCoordinator(presenter: presenter,
                                                   settings: StubSettings(excludedBundleIDs: []),
                                                   reader: reader,
                                                   translator: translator)

        coordinator.handleSelectionRequest()
        let reachedProvider = await waitUntil { await translator.requestCount == 1 }
        XCTAssertTrue(reachedProvider, "the confirmed selection reaches the provider")
        await translator.complete(translation: "打开设置")
        await waitUntil { presenter.manualResults == ["打开设置"] }

        let read = await reader.bodyReadCount
        XCTAssertEqual(read, 1)
        XCTAssertEqual(presenter.manualInputs, ["Open Settings"])
        XCTAssertTrue(presenter.manualPrompts.isEmpty)
        XCTAssertEqual(coordinator.lastSelectionSource, "com.example.reader")
    }

    func testASelectionReadIsDroppedWhenTheSourceIsExcludedMeanwhile() async {
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: false))
        await reader.setText("Secret")
        await reader.gateReads()
        let settings = StubSettings(excludedBundleIDs: [])
        let coordinator = makeSelectionCoordinator(presenter: presenter,
                                                   settings: settings,
                                                   reader: reader,
                                                   translator: translator)

        coordinator.handleSelectionRequest()
        let reading = await waitUntil { await reader.bodyReadCount == 1 }
        XCTAssertTrue(reading, "the read started")

        // The user excludes the application while its selection is being read.
        settings.excludedBundleIDs = ["com.example.reader"]
        coordinator.translationPolicyChanged()
        await reader.completeRead()
        await drain()

        let requests = await translator.requestCount
        XCTAssertEqual(requests, 0, "a selection that is no longer allowed is never sent")
        XCTAssertTrue(presenter.manualInputs.isEmpty, "and its text is never shown")
        XCTAssertNil(coordinator.lastSelectionSource)
    }

    func testDisabledSettingNeverStartsASelectionRead() async {
        let presenter = RecordingPresenter()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: false))
        await reader.setText("Open Settings")
        let coordinator = makeSelectionCoordinator(
            presenter: presenter,
            settings: StubSettings(isEnabled: false, excludedBundleIDs: []),
            reader: reader)

        coordinator.handleSelectionRequest()
        await drain()

        let focused = await reader.focusedCount
        XCTAssertEqual(focused, 0, "a disabled feature reads nothing")
        XCTAssertTrue(presenter.manualPrompts.isEmpty)
    }

    /// One registration means one delivery: the controller's press cannot start
    /// two reads.
    func testOneShortcutPressStartsExactlyOneSelectionRead() async {
        let presenter = RecordingPresenter()
        let reader = StubSelectionReader()
        await reader.setFocus(SelectionFocus(pid: 4242, isSecure: false))
        await reader.setText("Open Settings")
        let coordinator = makeSelectionCoordinator(presenter: presenter,
                                                   settings: StubSettings(excludedBundleIDs: []),
                                                   reader: reader)
        let registrar = RecordingRegistrar()
        let controller = SelectionShortcutController(coordinator: coordinator,
                                                     registrar: registrar,
                                                     shortcut: { .default })
        controller.refreshRegistration()

        registrar.press()
        await drain()

        let focused = await reader.focusedCount
        XCTAssertEqual(focused, 1)
    }

    // MARK: - R6: policy, key and session changes invalidate in-flight work

    func testDeletingTheKeyDropsAnAnswerThatIsAlreadyInFlight() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let cache = TranslationCache()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     cache: cache)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)

        // The key is deleted while the answer is on its way back.
        coordinator.translationCredentialsChanged()
        await translator.complete(translation: "收费", matching: "charge")
        await drain()

        XCTAssertTrue(presenter.translations.isEmpty, "an answer produced under the deleted key is not shown")
        let cached = await cache.count
        XCTAssertEqual(cached, 0, "and it is not written back to the cache")
    }

    func testExcludingTheSourceDropsAnAnswerThatIsAlreadyInFlight() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let cache = TranslationCache()
        let settings = StubSettings(excludedBundleIDs: [])
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: settings,
                                                     translator: translator,
                                                     cache: cache)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)

        settings.excludedBundleIDs = ["com.example.reader"]
        coordinator.translationPolicyChanged()
        await translator.complete(translation: "收费", matching: "charge")
        await drain()

        XCTAssertTrue(presenter.translations.isEmpty, "an answer for a source that is now excluded is not shown")
        let cached = await cache.count
        XCTAssertEqual(cached, 0, "and it is not written back to the cache")
    }

    func testLockingTheSessionClearsTheCacheAndDropsInFlightWork() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let cache = TranslationCache()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     cache: cache)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)
        await translator.complete(translation: "收费", matching: "charge")
        let stored = await waitUntil { await cache.count == 1 }
        XCTAssertTrue(stored, "the first answer really was cached")

        // A second query is in flight when the screen locks.
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.0))
        coordinator.pointerMoved(to: CGPoint(x: 300, y: 300), at: at(1.4))
        await extractor.waitForRequests(2)
        await extractor.complete(generation: 2, text: "fee")
        await drain()
        await translator.waitForRequests(2)

        coordinator.sessionWentInactive()
        await translator.complete(translation: "费用", matching: "fee")
        let cleared = await waitUntil { await cache.count == 0 }
        XCTAssertTrue(cleared, "the cache is dropped when the session ends")

        XCTAssertEqual(presenter.translations, ["收费"], "the answer in flight when the session ended is not shown")
    }

    func testTurningTranslationOffDropsAnAnswerThatIsAlreadyInFlight() async {
        let extractor = GatedExtractor()
        let presenter = RecordingPresenter()
        let translator = FakeTranslator()
        let cache = TranslationCache()
        let coordinator = makeTranslatingCoordinator(extractor: extractor,
                                                     presenter: presenter,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: translator,
                                                     cache: cache)
        await beginTranslating(extractor: extractor, presenter: presenter, coordinator: coordinator, word: "charge")
        await translator.waitForRequests(1)

        // The user turns cloud translation off while the answer is on its way.
        coordinator.translationDisabled()
        await translator.complete(translation: "收费", matching: "charge")
        await drain()

        XCTAssertTrue(presenter.translations.isEmpty, "an answer started before the switch is not shown")
        let cached = await cache.count
        XCTAssertEqual(cached, 0, "and it is not written back to the cache")
    }

    // MARK: - R5: the manual window's own buttons

    /// The binding itself, not just the method behind it: a manual Copy must
    /// never reach the hovering card's snapshot.
    func testTheManualCopyButtonCopiesTheManualResult() async {
        let card = RecordingPresenter()
        let coordinator = makeTranslatingCoordinator(extractor: GatedExtractor(),
                                                     presenter: card,
                                                     settings: StubSettings(excludedBundleIDs: []),
                                                     translator: FakeTranslator())
        let manual = RecordingPresenter()
        coordinator.attachManualPresenter(manual)

        let actions = CardActions()
        ManualActionWiring.wire(actions, coordinator: coordinator)
        actions.onCopy?()

        XCTAssertEqual(manual.copyCount, 1, "Copy result copies the manual window's own result")
        XCTAssertEqual(card.copyCount, 0, "and never the hovering card")
    }
}

// MARK: - Test doubles

@MainActor
final class StubSettings: SettingsReading {
    var isEnabled: Bool
    var useRightOption: Bool
    var excludedBundleIDs: Set<String>
    var isOCRFallbackEnabled: Bool
    init(isEnabled: Bool = true,
         useRightOption: Bool = true,
         excludedBundleIDs: Set<String>,
         isOCRFallbackEnabled: Bool = false) {
        self.isEnabled = isEnabled
        self.useRightOption = useRightOption
        self.excludedBundleIDs = excludedBundleIDs
        self.isOCRFallbackEnabled = isOCRFallbackEnabled
    }
}

/// A locator whose answer can change while a query is in flight.
@MainActor
final class MutableStubLocator: SourceLocating {
    var source: SourceApp?
    init(source: SourceApp?) { self.source = source }
    func currentSource(at point: CGPoint) -> SourceApp? { source }
}

@MainActor
final class StubLocator: SourceLocating {
    let pid: pid_t
    let bundleID: String?
    init(pid: pid_t, bundleID: String?) {
        self.pid = pid
        self.bundleID = bundleID
    }
    func currentSource(at point: CGPoint) -> SourceApp? {
        guard pid > 0 else { return nil }
        return SourceApp(pid: pid, bundleID: bundleID)
    }
}

/// A wordbook stand-in: fixed answers, and a record of what was asked for.
actor StubWordSenseProvider: WordSenseProviding {
    private let entries: [String: WordEntry]
    private(set) var asked: [String] = []

    init(entries: [String: WordEntry]) { self.entries = entries }

    func entry(for word: String) async -> WordEntry? {
        asked.append(word)
        return entries[word.lowercased()]
    }
}

@MainActor
final class RecordingPresenter: CardPresenting, ManualPresenting {
    var presented: [ExtractionSnapshot] = []
    var translations: [String] = []
    /// Every dictionary answer the coordinator handed to the card.
    var dictionaries: [WordEntry] = []
    var translationFailures: [TranslationFailure] = []
    var translatingCount = 0
    var explanationLoadingCount = 0
    var explanations: [String] = []
    var explanationFailures: [TranslationFailure] = []
    var notes: [String] = []
    /// Every status line the coordinator asked for, in order.
    var statuses: [String] = []
    var statusPoints: [CGPoint] = []
    var statusDismissCount = 0
    var copyCount = 0
    var manualInputs: [String?] = []
    var manualPrompts: [ExtractionFailure?] = []
    var manualResults: [String] = []
    var manualFailure: TranslationFailure?
    var dismissCount = 0
    var buttonsVisible = false
    var interactive = false
    var pinned = false
    var cardFrame: CGRect?

    func present(_ snapshot: ExtractionSnapshot) { presented.append(snapshot) }
    func setTranslating() { translatingCount += 1 }
    func setTranslation(_ result: TranslationResult, for snapshot: ExtractionSnapshot) {
        translations.append(result.text)
    }
    func setTranslationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot) {
        translationFailures.append(failure)
    }
    func setDictionary(_ entry: WordEntry, for snapshot: ExtractionSnapshot) {
        dictionaries.append(entry)
    }
    func copyDisplayedText() { copyCount += 1 }
    func setExplanationLoading() { explanationLoadingCount += 1 }
    func setExplanation(_ text: String, for snapshot: ExtractionSnapshot) { explanations.append(text) }
    func setExplanationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot) {
        explanationFailures.append(failure)
    }
    func showNote(_ note: String) { notes.append(note) }
    func showStatus(_ text: String, at point: CGPoint) {
        statuses.append(text)
        statusPoints.append(point)
    }
    func dismissStatus() { statusDismissCount += 1 }
    func setButtonsVisible(_ visible: Bool) { buttonsVisible = visible }
    func setInteractive(_ interactive: Bool) { self.interactive = interactive }
    func setPinned(_ pinned: Bool) { self.pinned = pinned }
    func dismiss() { dismissCount += 1 }
    func containsScreenPoint(_ point: CGPoint) -> Bool {
        guard let cardFrame else { return false }
        return cardFrame.contains(point)
    }

    // MARK: ManualPresenting

    func showManualInput(_ text: String?, failure: TranslationFailure?) {
        manualInputs.append(text)
        manualFailure = failure
    }

    func promptForManualPaste(_ reason: ExtractionFailure?) {
        manualPrompts.append(reason)
    }

    func setManualResult(_ translation: String, snapshotText: String) {
        manualResults.append(translation)
    }
}

@MainActor
final class SilentScheduler: TickScheduling {
    var started = 0
    var stopped = 0
    func startTicking(interval: TimeInterval, _ body: @escaping @MainActor (Date) -> Void) { started += 1 }
    func stopTicking() { stopped += 1 }
}

actor GatedExtractor: TextExtracting {
    private var continuations: [UInt64: CheckedContinuation<ExtractionSnapshot, Error>] = [:]
    private var requests: [ExtractionRequest] = []

    var requestCount: Int { requests.count }

    var requestedModes: [QueryMode] { requests.map(\.mode) }

    func mode(ofGeneration generation: UInt64) -> QueryMode? {
        requests.first { $0.generation == generation }?.mode
    }

    func extract(_ request: ExtractionRequest) async throws -> ExtractionSnapshot {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[request.generation] = continuation
        }
    }

    func waitForRequests(_ count: Int) async {
        for _ in 0..<5_000 {
            if requests.count >= count { return }
            await Task.yield()
        }
    }

    func complete(generation: UInt64, text: String, scope: ExtractionScope = .word) {
        guard let continuation = continuations.removeValue(forKey: generation) else { return }
        continuation.resume(returning: ExtractionSnapshot(text: text,
                                                          context: nil,
                                                          scope: scope,
                                                          completeness: .complete,
                                                          source: .accessibility,
                                                          sourcePID: 4242,
                                                          sourceBundleID: "com.example.reader",
                                                          wordFrame: nil,
                                                          generation: generation))
    }

    func fail(generation: UInt64, error: ExtractionFailure) {
        guard let continuation = continuations.removeValue(forKey: generation) else { return }
        continuation.resume(throwing: error)
    }
}

/// Fake screenshot fallback: counts attempts and answers immediately. No
/// capture, no Vision and no permission are involved.
actor RecordingOCRExtractor: TextExtracting {
    private var requests: [ExtractionRequest] = []
    var requestCount: Int { requests.count }

    func extract(_ request: ExtractionRequest) async throws -> ExtractionSnapshot {
        requests.append(request)
        return ExtractionSnapshot(text: "Image sentence",
                                  context: nil,
                                  scope: .sentence,
                                  completeness: .partial,
                                  source: .ocr,
                                  sourcePID: request.sourcePID,
                                  sourceBundleID: request.sourceBundleID,
                                  wordFrame: nil,
                                  generation: request.generation)
    }
}

/// Fake translation provider: no network, explicit ordering, no real key.
actor FakeTranslator: TranslationService {
    private var pending: [(text: String, continuation: CheckedContinuation<TranslationResult, Error>)] = []
    private var received: [TranslationRequest] = []
    private var receivedModels: [String] = []

    var requestCount: Int { received.count }
    /// The models the app actually asked for, in request order.
    var models: [String] { receivedModels }
    /// The modes the app actually asked for, in request order.
    var modes: [QueryMode] { received.map(\.mode) }

    func translate(_ request: TranslationRequest, apiKey: String, model: String) async throws -> TranslationResult {
        received.append(request)
        receivedModels.append(model)
        return try await withCheckedThrowingContinuation { continuation in
            pending.append((request.text, continuation))
        }
    }

    func waitForRequests(_ count: Int) async {
        for _ in 0..<5_000 {
            if received.count >= count { return }
            await Task.yield()
        }
    }

    /// Completes the oldest pending request with `translation` as the answer.
    func complete(translation: String, matching requestText: String? = nil) {
        let index: Int?
        if let requestText {
            index = pending.firstIndex { $0.text == requestText }
        } else {
            index = pending.isEmpty ? nil : 0
        }
        guard let index else { return }
        let entry = pending.remove(at: index)
        entry.continuation.resume(returning: TranslationResult(text: translation,
                                                               model: "test-model",
                                                               provider: "deepseek",
                                                               promptVersion: TranslationRequestBuilder.promptVersion))
    }

    /// Completes the newest pending request, whatever text it carries: the
    /// explanation of a word shares that word's text with its translation.
    func completeNewest(translation: String) {
        guard !pending.isEmpty else { return }
        let entry = pending.removeLast()
        entry.continuation.resume(returning: TranslationResult(text: translation,
                                                               model: "test-model",
                                                               provider: "deepseek",
                                                               promptVersion: TranslationRequestBuilder.promptVersion))
    }

    func complete(failure: TranslationFailure) {
        guard !pending.isEmpty else { return }
        let entry = pending.removeFirst()
        entry.continuation.resume(throwing: failure)
    }
}

/// Fake selection entry: the two-step read without Accessibility. The body read
/// can be held open so a test can change the rules while it is in flight, and a
/// focus change makes it return nothing — which is what the real extractor does
/// when the focused control is no longer the one whose source was confirmed.
actor StubSelectionReader: SelectionReading {
    private var focus: SelectionFocus?
    private var text: String?
    private var gated = false
    private var focusCount = 0
    private var readCount = 0
    private var pending: CheckedContinuation<String?, Never>?

    var focusedCount: Int { focusCount }
    var bodyReadCount: Int { readCount }

    func setFocus(_ focus: SelectionFocus?) { self.focus = focus }
    func setText(_ text: String?) { self.text = text }
    func gateReads() { gated = true }

    func focusedControl() async -> SelectionFocus? {
        focusCount += 1
        return focus
    }

    func selectedText(belongingTo ownerPID: pid_t) async -> String? {
        readCount += 1
        guard let focus, focus.pid == ownerPID else { return nil }
        guard gated else { return text }
        return await withCheckedContinuation { continuation in
            pending = continuation
        }
    }

    func completeRead() {
        guard let pending else { return }
        self.pending = nil
        pending.resume(returning: text)
    }
}
