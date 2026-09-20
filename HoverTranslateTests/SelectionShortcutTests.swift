import AppKit
import Carbon.HIToolbox
import XCTest
@testable import HoverTranslate

/// v0.4: the selection shortcut is a real setting.
/// v0.5 fix: it is registered through the public hot-key API, so the system's
/// own answer — registered, refused as a conflict, or failed — is what the app
/// reports, instead of a key monitor that cannot be told "no".
@MainActor
final class SelectionShortcutTests: XCTestCase {
    func testTheDefaultPresetIsControlCommandT() {
        XCTAssertEqual(SelectionShortcut.default.keyCode, 17)
        XCTAssertEqual(SelectionShortcut.default.modifiers, [.control, .command])
        XCTAssertEqual(SelectionShortcut.default.label, "Control-Command-T")
    }

    /// The presets are handed to the system as Carbon modifier bits, so the
    /// mapping has to be exact.
    func testCarbonModifiersMatchThePreset() {
        XCTAssertEqual(SelectionShortcut.default.carbonModifiers,
                       UInt32(controlKey) | UInt32(cmdKey))
        XCTAssertEqual(SelectionShortcut.choice(at: 3).carbonModifiers,
                       UInt32(optionKey) | UInt32(cmdKey))
    }

    func testAnOutOfRangeStoredIndexFallsBackToTheFirstPreset() {
        XCTAssertEqual(SelectionShortcut.choice(at: -1), .default)
        XCTAssertEqual(SelectionShortcut.choice(at: 99), .default)
        XCTAssertEqual(SelectionShortcut.choice(at: 0), .default)
    }

    func testEveryPresetNeedsBothACommandAndAControlOrOptionModifier() {
        // Registering a bare key would take it away from every application;
        // every preset is an explicit combination.
        for shortcut in SelectionShortcut.choices {
            XCTAssertTrue(shortcut.modifiers.contains(.command), shortcut.label)
            XCTAssertTrue(shortcut.modifiers.contains(.control) || shortcut.modifiers.contains(.option),
                          shortcut.label)
            XCTAssertFalse(shortcut.label.isEmpty)
        }
    }

    func testTheSystemAnswerBecomesRegisteredConflictOrFailure() {
        XCTAssertEqual(SelectionShortcutController.state(for: noErr), .registered)
        XCTAssertEqual(SelectionShortcutController.state(for: OSStatus(eventHotKeyExistsErr)), .conflict)
        XCTAssertEqual(SelectionShortcutController.state(for: -50), .failed(-50))
    }

    func testTheStoredPresetIsWhatGetsRegistered() {
        let registrar = RecordingRegistrar()
        let controller = SelectionShortcutController(coordinator: makeCoordinator(),
                                                     registrar: registrar,
                                                     shortcut: { SelectionShortcut.choice(at: 2) })

        controller.refreshRegistration()

        XCTAssertEqual(registrar.registered, [SelectionShortcut.choice(at: 2)])
        XCTAssertEqual(controller.state, .registered)
    }

    func testChangingThePresetRegistersTheNewOneAndReleasesTheOld() {
        var index = 0
        let registrar = RecordingRegistrar()
        let controller = SelectionShortcutController(coordinator: makeCoordinator(),
                                                     registrar: registrar,
                                                     shortcut: { SelectionShortcut.choice(at: index) })

        controller.refreshRegistration()
        index = 1
        controller.refreshRegistration()

        XCTAssertEqual(registrar.registered, [SelectionShortcut.choice(at: 0), SelectionShortcut.choice(at: 1)])
        XCTAssertGreaterThanOrEqual(registrar.unregisterCount, 1, "the previous combination is released first")
    }

    func testARefusedCombinationIsReportedAsAConflict() {
        let registrar = RecordingRegistrar(statuses: [OSStatus(eventHotKeyExistsErr)])
        let controller = SelectionShortcutController(coordinator: makeCoordinator(), registrar: registrar)

        controller.refreshRegistration()

        XCTAssertEqual(controller.state, .conflict)
        let summary = controller.state.summary(label: controller.currentShortcut.label,
                                               canReadSelection: true)
        XCTAssertTrue(summary.contains("another application"), summary)
        XCTAssertTrue(summary.contains("Settings"), summary)
    }

    func testStoppingReleasesTheCombination() {
        let registrar = RecordingRegistrar()
        let controller = SelectionShortcutController(coordinator: makeCoordinator(), registrar: registrar)

        controller.refreshRegistration()
        controller.stop()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertGreaterThanOrEqual(registrar.unregisterCount, 1)
    }

    /// The wording is the only thing the user sees, so it has to say what the
    /// registration needs instead of claiming the shortcut works.
    func testTheSummaryNamesTheMissingAccessibilityPermission() {
        let label = SelectionShortcut.default.label
        XCTAssertEqual(SelectionRegistrationState.registered.summary(label: label, canReadSelection: true),
                       "Shortcut registered: \(label).")
        XCTAssertTrue(SelectionRegistrationState.registered
            .summary(label: label, canReadSelection: false)
            .contains("Accessibility"))
        XCTAssertTrue(SelectionRegistrationState.failed(-50).summary(label: label, canReadSelection: true)
            .contains(label))
    }

    /// The controller needs a coordinator to deliver a press to; none of these
    /// tests press the key, so it only has to exist.
    private func makeCoordinator() -> TranslationCoordinator {
        TranslationCoordinator(extractor: SelectionTestExtractor(),
                               presenter: SelectionTestPresenter(),
                               locator: StubLocator(pid: 4242, bundleID: "com.example.reader"),
                               settings: StubSettings(excludedBundleIDs: []),
                               scheduler: SilentScheduler())
    }
}

/// Records what the controller asked the system for, and lets a test press the
/// registered combination without a keyboard.
@MainActor
final class RecordingRegistrar: HotKeyRegistering {
    private var statuses: [OSStatus]
    private(set) var registered: [SelectionShortcut] = []
    private(set) var unregisterCount = 0
    private var onPress: (() -> Void)?

    init(statuses: [OSStatus] = []) {
        self.statuses = statuses
    }

    func register(_ shortcut: SelectionShortcut, onPress: @escaping () -> Void) -> OSStatus {
        registered.append(shortcut)
        self.onPress = onPress
        return statuses.isEmpty ? noErr : statuses.removeFirst()
    }

    func unregister() {
        unregisterCount += 1
        onPress = nil
    }

    func press() { onPress?() }
}

/// Never extracts: these tests are about the registration, not about text.
struct SelectionTestExtractor: TextExtracting {
    func extract(_ request: ExtractionRequest) async throws -> ExtractionSnapshot {
        throw ExtractionFailure.noText
    }
}

@MainActor
final class SelectionTestPresenter: CardPresenting {
    func present(_ snapshot: ExtractionSnapshot) {}
    func setTranslating() {}
    func setTranslation(_ result: TranslationResult, for snapshot: ExtractionSnapshot) {}
    func setTranslationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot) {}
    func setDictionary(_ entry: WordEntry, for snapshot: ExtractionSnapshot) {}
    func setExplanationLoading() {}
    func setExplanation(_ text: String, for snapshot: ExtractionSnapshot) {}
    func setExplanationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot) {}
    func showNote(_ note: String) {}
    func showStatus(_ text: String, at point: CGPoint) {}
    func dismissStatus() {}
    func copyDisplayedText() {}
    func dismiss() {}
    func containsScreenPoint(_ point: CGPoint) -> Bool { false }
    func setButtonsVisible(_ visible: Bool) {}
    func setInteractive(_ interactive: Bool) {}
    func setPinned(_ pinned: Bool) {}
}
