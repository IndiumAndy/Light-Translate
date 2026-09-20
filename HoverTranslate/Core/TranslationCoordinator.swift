import AppKit
import Foundation
import os

struct SourceApp: Equatable, Sendable {
    let pid: pid_t
    let bundleID: String?
    /// The window the pointer is over, from the same front-to-back list read.
    var windowID: CGWindowID? = nil
}

@MainActor
protocol SourceLocating: AnyObject {
    func currentSource(at point: CGPoint) -> SourceApp?
}

/// One on-screen window, reduced to what the source decision needs.
struct PointerWindow: Equatable, Sendable {
    let ownerPID: pid_t
    let layer: Int
    /// Bounds in CoreGraphics screen space (origin at the top-left of the primary
    /// display), which is also the Accessibility space.
    let bounds: CGRect
    /// CoreGraphics window number. Window geometry and identity need no Screen
    /// Recording permission; only content does.
    var windowID: CGWindowID = 0
}

/// Pure selection over the window list: the first window in front-to-back order
/// that contains the point and does not belong to this process.
enum PointerWindowPicker {
    static func topmostWindow(_ windows: [PointerWindow],
                              at point: CGPoint,
                              excluding excludedPID: pid_t) -> PointerWindow? {
        windows.first {
            // An opened menu has its own window. Selecting the normal window
            // underneath it would misattribute AX and capture unrelated content.
            ($0.layer == 0 || $0.layer == NSWindow.Level.popUpMenu.rawValue)
                && $0.ownerPID != excludedPID && $0.bounds.contains(point)
        }
    }

    static func topmostOwner(_ windows: [PointerWindow],
                             at point: CGPoint,
                             excluding excludedPID: pid_t) -> pid_t? {
        topmostWindow(windows, at: point, excluding: excludedPID)?.ownerPID
    }
}

/// Reads the on-screen window list. Owner and geometry need no Screen Recording
/// permission and no window content is requested.
enum WindowList {
    static func onScreen() -> [PointerWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? Int,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else { return nil }
            return PointerWindow(ownerPID: pid_t(owner),
                                 layer: layer,
                                 bounds: CGRect(x: x, y: y, width: width, height: height),
                                 windowID: CGWindowID(number))
        }
    }
}

/// Uses the application that owns the topmost window under the pointer.
///
/// The frontmost application is not the same thing: moving the pointer over a
/// window without clicking it leaves the previous application frontmost, and
/// every hover then fails with "the pointed window belongs to another
/// application".
@MainActor
final class PointerWindowSourceLocator: SourceLocating {
    func currentSource(at point: CGPoint) -> SourceApp? {
        let axPoint = CoordinateMapper.appKitToAX(point, primaryFrame: CGDisplayBounds(CGMainDisplayID()))
        guard let window = PointerWindowPicker.topmostWindow(WindowList.onScreen(),
                                                            at: axPoint,
                                                            excluding: getpid()),
              window.ownerPID > 0 else { return nil }
        return SourceApp(pid: window.ownerPID,
                         bundleID: NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier,
                         windowID: window.windowID)
    }
}

@MainActor
protocol SettingsReading: AnyObject {
    var isEnabled: Bool { get }
    var useRightOption: Bool { get }
    /// Applications the user excluded. Empty means every application is read.
    var excludedBundleIDs: Set<String> { get }
    /// v0.3: whether the screenshot fallback may be attempted at all.
    var isOCRFallbackEnabled: Bool { get }
}

/// The manual-entry window. A narrower role than `CardPresenting`: a manual
/// request must never touch the hovering card, and the card must never show the
/// manual editor.
@MainActor
protocol ManualPresenting: AnyObject {
    func showManualInput(_ text: String?, failure: TranslationFailure?)
    /// Opens an empty editor and says what to paste. Nothing is read from the
    /// clipboard for the user: pasting stays an explicit action.
    func promptForManualPaste(_ reason: ExtractionFailure?)
    func setManualResult(_ translation: String, snapshotText: String)
    func copyDisplayedText()
}

/// Everything the coordinator needs for translation, kept in one optional
/// value: without it the app is exactly v0.1 and makes no network calls.
struct TranslationContext {
    let service: TranslationService
    let cache: TranslationCache?
    let configuration: @MainActor () -> TranslationConfiguration
}

@MainActor
protocol CardPresenting: AnyObject {
    func present(_ snapshot: ExtractionSnapshot)
    /// Marks the request as in flight without inventing a translation.
    func setTranslating()
    /// The visible English always comes from the local snapshot, never from the
    /// model restating the source.
    func setTranslation(_ result: TranslationResult, for snapshot: ExtractionSnapshot)
    /// A failed translation leaves the original text readable and states why.
    func setTranslationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot)
    /// The offline meanings of the word on the card, when the app has them.
    func setDictionary(_ entry: WordEntry, for snapshot: ExtractionSnapshot)
    /// v0.4: the explanation the user explicitly asked for, labelled as a model
    /// answer rather than a dictionary entry.
    func setExplanationLoading()
    func setExplanation(_ text: String, for snapshot: ExtractionSnapshot)
    func setExplanationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot)
    /// A short status line that is neither a translation nor an explanation
    /// (already saved, nothing to save, saved list unreadable).
    func showNote(_ note: String)
    /// A short, non-activating status that is neither a translation nor a result:
    /// a capture that is still waiting, or why nothing could be read here. It
    /// never carries text from the source, and a pinned card is never covered.
    func showStatus(_ text: String, at point: CGPoint)
    func dismissStatus()
    /// Writes the clipboard only when the user clicks Copy. Never automatic.
    func copyDisplayedText()
    func dismiss()
    func containsScreenPoint(_ point: CGPoint) -> Bool
    func setButtonsVisible(_ visible: Bool)
    func setInteractive(_ interactive: Bool)
    func setPinned(_ pinned: Bool)
}

/// Injectable ticker so tests never depend on wall-clock timers.
@MainActor
protocol TickScheduling: AnyObject {
    func startTicking(interval: TimeInterval, _ body: @escaping @MainActor (Date) -> Void)
    func stopTicking()
}

@MainActor
final class RunLoopTickScheduler: TickScheduling {
    private var timer: Timer?

    func startTicking(interval: TimeInterval, _ body: @escaping @MainActor (Date) -> Void) {
        stopTicking()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { body(Date()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

/// Owns the whole v0.1 flow: trigger key state, dwell timing, generation
/// validity, allow list enforcement and card lifecycle. Everything here runs on
/// the main actor and never performs blocking Accessibility work itself.
@MainActor
final class TranslationCoordinator: ObservableObject {
    @Published private(set) var lastScope: ExtractionScope?
    @Published private(set) var lastFailure: ExtractionFailure?
    @Published private(set) var lastTranslationFailure: TranslationFailure?
    @Published private(set) var lastTranslationText: String?
    @Published private(set) var lastExplanationText: String?
    @Published private(set) var lastExplanationFailure: TranslationFailure?
    @Published private(set) var isTriggerHeld = false

    /// Number of extractions actually started; used by tests and for a manual
    /// "nothing is read until triggered" check.
    private(set) var extractionStarts = 0

    var cardPhase: CardLifecycle.Phase { lifecycle.phase }

    private let extractor: TextExtracting
    /// The selection entry reads the focused control instead of the window under
    /// the pointer, which is a different source and must never stand in for it.
    private let selectionReader: SelectionReading
    /// Resolves the application a focused control belongs to. Injectable so a
    /// test can decide the source without a real running application.
    private let bundleIdentifierForPID: (pid_t) -> String?
    private let presenter: CardPresenting
    private let locator: SourceLocating
    private let settings: SettingsReading
    private let scheduler: TickScheduling
    private let now: () -> Date
    private let pointerLocation: () -> CGPoint
    private var translation: TranslationContext?
    /// v0.3: the screenshot fallback, and whether Screen Recording is granted.
    /// The coordinator decides *whether* to fall back; the extractor only knows
    /// how to capture.
    private let ocrFallback: TextExtracting?
    private let captureAuthorized: () -> Bool
    /// The offline wordbook, when the app has one to hand. Without it the card
    /// shows no dictionary section.
    private let senseProvider: WordSenseProviding?
    private var ocrLimiter = OCRRateLimiter()
    /// At most one deferred capture. A rate-limited fallback is a wait, not a
    /// failure, so it is held here until its earliest moment arrives.
    private var pendingOCR: PendingOCR?
    /// True while a capture or its recognition is actually running, so a due
    /// retry can never overlap one.
    private var ocrInFlight = false
    private var ocrRetryTask: Task<Void, Never>?
    /// Until when the current status line stays on screen.
    private var statusUntil: Date?
    private var lastStatus: (text: String, shownAt: Date)?

    /// A capture the rate limit deferred, with everything needed to re-check it
    /// before it is allowed to run.
    private struct PendingOCR {
        let request: ExtractionRequest
        let generation: UInt64
        let failure: ExtractionFailure
        let notBefore: Date
    }

    /// How long a status line stays, and how often the same line may return.
    /// Design initial values, not measured.
    private static let statusDuration: TimeInterval = 1.4
    private static let statusThrottle: TimeInterval = 1.5

    /// Number of OCR attempts. Covers "nothing is captured while idle" checks.
    private(set) var ocrStarts = 0
    /// Number of answers served from the cache without a request.
    private(set) var cacheHits = 0
    /// Number of explanation requests actually sent. Nothing is sent before the
    /// user presses Explain, which is what this counter is checked against.
    private(set) var explanationStarts = 0

    /// v0.4: the user's saved entries. Writes happen only from Save.
    private let learning: LearningStore
    /// Called after an entry was written, so an open saved-entries window can
    /// reload instead of showing a stale list.
    var didSaveEntry: (() -> Void)?
    private var explanationTask: Task<Void, Never>?

    /// The manual-entry window presenter. Separate from `presenter` so a manual
    /// request never touches the hovering card.
    private weak var manualPresenter: ManualPresenting?
    /// Provided by the app layer to bring the manual window to the front. It
    /// never reads the clipboard: the editor is filled by the user.
    var revealManualWindow: (() -> Void)?

    /// Number of translation requests actually started. Tests use it to prove
    /// that a cache hit or a missing key costs no request.
    private(set) var translationStarts = 0

    private var gate = RequestGate()
    private var lifecycle = CardLifecycle()
    private var dwell = HoverDwell()
    private var task: Task<Void, Never>?
    /// The wordbook lookup for the snapshot currently on the card.
    private var dictionaryTask: Task<Void, Never>?
    private var shownSnapshot: ExtractionSnapshot?
    private var rightOptionDown = false
    private var leftOptionDown = false
    private var controlDown = false
    /// The mode of the gesture in progress; fixed while the trigger is held.
    private var activeMode: QueryMode = .word
    private var pointerInsideCard = false
    private var isTicking = false
    private let log = Logger(subsystem: "com.atat.HoverTranslate", category: "coordinator")

    init(extractor: TextExtracting,
         presenter: CardPresenting,
         locator: SourceLocating,
         settings: SettingsReading,
         translation: TranslationContext? = nil,
         senses: WordSenseProviding? = nil,
         ocrFallback: TextExtracting? = nil,
         captureAuthorized: @escaping () -> Bool = { false },
         learning: LearningStore = .applicationSupport(),
         selectionReader: SelectionReading = SelectionTextExtractor(),
         bundleIdentifierForPID: @escaping (pid_t) -> String? = {
             NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
         },
         scheduler: TickScheduling? = nil,
         now: @escaping () -> Date = Date.init,
         pointerLocation: (() -> CGPoint)? = nil) {
        self.extractor = extractor
        self.selectionReader = selectionReader
        self.bundleIdentifierForPID = bundleIdentifierForPID
        self.presenter = presenter
        self.locator = locator
        self.settings = settings
        self.translation = translation
        self.senseProvider = senses
        self.ocrFallback = ocrFallback
        self.captureAuthorized = captureAuthorized
        self.learning = learning
        self.scheduler = scheduler ?? RunLoopTickScheduler()
        self.now = now
        self.pointerLocation = pointerLocation ?? { NSEvent.mouseLocation }
    }

    // MARK: - Trigger key

    func optionStateChanged(right: Bool, left: Bool, control: Bool = false) {
        rightOptionDown = right
        leftOptionDown = left
        controlDown = control
        updateTriggerState()
    }

    /// The mode the current gesture asks for: Control upgrades word to sentence.
    private var requestedMode: QueryMode? {
        TriggerPolicy.mode(rightOption: rightOptionDown,
                           leftOption: leftOptionDown,
                           control: controlDown,
                           enabled: settings.isEnabled,
                           useRightOption: settings.useRightOption)
    }

    var triggerHeld: Bool { requestedMode != nil }

    private var triggerWasHeld = false

    private func updateTriggerState() {
        let held = triggerHeld
        let mode = requestedMode ?? .word
        if held != triggerWasHeld {
            triggerWasHeld = held
            isTriggerHeld = held
            activeMode = mode
            dwell.reset()
            if held {
                samplePointer(at: pointerLocation(), now: now())
                startTickingIfNeeded()
            } else {
                triggerReleased()
                startTickingIfNeeded()
                stopTickingIfIdle()
            }
            return
        }
        guard held, mode != activeMode else { return }
        // Control was pressed or released while the trigger stayed held. The
        // request the previous mode started is already the wrong kind of answer,
        // so it is invalidated and the dwell restarts under the new mode.
        activeMode = mode
        cancelOutstanding(hideCard: true)
        lastFailure = nil
        dwell.reset()
    }

    private func triggerReleased() {
        guard lifecycle.phase == .live else { return }
        guard shownSnapshot != nil else {
            // Nothing was shown yet: drop the loading state, and a late result
            // must not bring the card back.
            cancelOutstanding(hideCard: true)
            return
        }
        lifecycle.release(now: now())
        // Releasing the trigger invalidates the generation without hiding the
        // card: a translation that was still in flight must not appear after
        // the user let go, and the next action starts a fresh generation.
        discardOutstandingWork()
        presenter.setButtonsVisible(true)
        presenter.setInteractive(true)
    }

    /// Invalidates the current generation and stops the tasks, leaving the
    /// visible card and its already-shown content alone.
    private func discardOutstandingWork() {
        gate.invalidate()
        task?.cancel()
        task = nil
        translationTask?.cancel()
        translationTask = nil
        dictionaryTask?.cancel()
        dictionaryTask = nil
        pendingOCR = nil
        ocrRetryTask?.cancel()
        ocrRetryTask = nil
        dismissStatus()
    }

    // MARK: - Pointer

    func pointerMoved(to point: CGPoint, at date: Date) {
        handlePointer(point, now: date)
    }

    func tick(now date: Date) {
        retryDeferredOCRIfDue(now: date)
        if isTriggerHeld, lifecycle.acceptsNewContent {
            samplePointer(at: pointerLocation(), now: date)
        }
        if lifecycle.shouldClose(now: date) {
            closeCard()
        }
        dismissStatusIfDue(now: date)
        stopTickingIfIdle()
    }

    private func samplePointer(at point: CGPoint, now date: Date) {
        guard isTriggerHeld, lifecycle.acceptsNewContent else { return }
        switch dwell.pointerMoved(to: point, at: date) {
        case .start:
            startExtraction(at: point, now: date)
        case .restart:
            cancelOutstanding(hideCard: true)
        case .none:
            break
        }
    }

    private func handlePointer(_ point: CGPoint, now date: Date) {
        // The card is part of the screen: never extract from it, and pause the
        // frozen-card close while the pointer is inside.
        if presenter.containsScreenPoint(point) {
            if !pointerInsideCard {
                pointerInsideCard = true
                lifecycle.pointerInside()
            }
            return
        }
        if pointerInsideCard {
            pointerInsideCard = false
            lifecycle.pointerOutside(now: date)
            startTickingIfNeeded()
        }
        samplePointer(at: point, now: date)
    }

    // MARK: - Other input

    /// Any ordinary key press, click, scroll or source change cancels work that
    /// is not pinned. Never consumes or replays the original event.
    func otherInput(at point: CGPoint) {
        guard lifecycle.phase != .pinned else { return }
        if presenter.containsScreenPoint(point) { return }
        externalChange()
    }

    func externalChange() {
        cancelOutstanding(hideCard: true)
        dwell.reset()
        stopTickingIfIdle()
    }

    // MARK: - Card buttons

    func pin() {
        switch lifecycle.phase {
        case .live, .frozen:
            lifecycle.pin()
            presenter.setPinned(true)
            presenter.setButtonsVisible(true)
            presenter.setInteractive(true)
            stopTickingIfIdle()
        case .hidden, .pinned:
            break
        }
    }

    func closeCard() {
        lifecycle.dismiss()
        presenter.dismiss()
        presenter.setPinned(false)
        dwell.reset()
        stopTickingIfIdle()
    }

    // MARK: - Extraction

    private func startExtraction(at point: CGPoint, now date: Date) {
        guard let source = locator.currentSource(at: point),
              source.pid > 0,
              source.pid != getpid() else {
            log.debug("no source window under the pointer")
            lastFailure = .unknownOwner
            return
        }
        log.debug("source pid=\(source.pid, privacy: .public) bundle=\(source.bundleID ?? "-", privacy: .public)")
        // Every application is readable unless the user excluded it. A source
        // with no bundle identifier cannot be attributed at all, so it is
        // refused rather than guessed at.
        guard let bundleID = source.bundleID, !bundleID.isEmpty else {
            cancelOutstanding(hideCard: true)
            lastScope = nil
            lastFailure = .unknownOwner
            return
        }
        guard SourcePolicy(excludedBundleIDs: settings.excludedBundleIDs).allows(bundleID: bundleID) else {
            cancelOutstanding(hideCard: true)
            lastScope = nil
            lastFailure = .appNotAllowed
            return
        }

        cancelOutstanding(hideCard: true)
        let generation = gate.begin()
        extractionStarts += 1
        lifecycle.showLive(now: date)
        presenter.setInteractive(false)
        presenter.setButtonsVisible(false)

        let request = ExtractionRequest(point: point,
                                        sourcePID: source.pid,
                                        sourceBundleID: source.bundleID,
                                        sourceWindowID: source.windowID,
                                        generation: generation,
                                        mode: activeMode)
        log.debug("extraction started")
        task = Task { [weak self] in
            guard let self else { return }
            let startedAt = self.now()
            do {
                let snapshot = try await self.extractor.extract(request)
                guard self.gate.accepts(generation) else {
                    self.log.debug("late result dropped")
                    return
                }
                self.logTiming(stage: "accessibility", generation: generation, startedAt: startedAt, outcome: "success")
                self.show(snapshot, generation: generation)
            } catch {
                guard self.gate.accepts(generation) else { return }
                let failure = (error as? ExtractionFailure) ?? .positionUnresolved
                self.logTiming(stage: "accessibility", generation: generation, startedAt: startedAt, outcome: failure.rawValue)
                self.handleOCRFallback(failure: failure, request: request, generation: generation)
            }
        }
    }

    /// The screenshot fallback for one failed Accessibility read.
    ///
    /// Three outcomes are deliberately distinct: the policy refuses (a decision,
    /// never a capture), the rate limit allows a capture now, or it allows one
    /// later. The last case is not a failure — it becomes one bounded wait that
    /// re-checks everything before it is allowed to run.
    ///
    /// The source is already confirmed: the exclusion list and the ownership of
    /// the window under the pointer were checked before the extraction started,
    /// and the request carries that confirmed window.
    private func handleOCRFallback(failure: ExtractionFailure,
                                   request: ExtractionRequest,
                                   generation: UInt64) {
        guard let ocr = ocrFallback,
              OCRFallbackPolicy.allows(failure,
                                       userEnabled: settings.isOCRFallbackEnabled,
                                       captureAuthorized: captureAuthorized(),
                                       sourceConfirmed: true) else {
            report(failure: failure)
            return
        }
        let date = now()
        if !ocrInFlight, ocrLimiter.takeSlot(now: date) {
            startOCR(ocr, request: request, generation: generation)
            return
        }
        // Either the interval has not passed, or a capture is still running:
        // exactly one wait, and never a second overlapping capture.
        let earliest = ocrLimiter.earliestStart(now: date) ?? date
        let notBefore = ocrInFlight
            ? max(earliest, date.addingTimeInterval(OCRRateLimiter.minimumInterval))
            : earliest
        pendingOCR = PendingOCR(request: request,
                               generation: generation,
                               failure: failure,
                               notBefore: notBefore)
        log.debug("capture deferred until the interval has passed")
        showStatus(OCRFallbackPolicy.waitingStatus, at: request.point)
    }

    /// v0.3: the only path that may take a screenshot. Everything that made this
    /// failure a decision rather than a limitation was refused by the policy
    /// before this point, and the frame never leaves memory.
    private func startOCR(_ ocr: TextExtracting, request: ExtractionRequest, generation: UInt64) {
        ocrStarts += 1
        ocrInFlight = true
        let startedAt = now()
        ocrRetryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await ocr.extract(request)
                self.ocrInFlight = false
                self.ocrRetryTask = nil
                guard self.gate.accepts(generation) else {
                    self.log.debug("late OCR result dropped")
                    return
                }
                self.logTiming(stage: "ocr", generation: generation, startedAt: startedAt, outcome: "success")
                self.show(snapshot, generation: generation)
            } catch {
                self.ocrInFlight = false
                self.ocrRetryTask = nil
                guard self.gate.accepts(generation) else { return }
                let ocrFailure = (error as? ExtractionFailure) ?? .noText
                self.logTiming(stage: "ocr", generation: generation, startedAt: startedAt, outcome: ocrFailure.rawValue)
                self.report(failure: ocrFailure)
            }
        }
    }

    /// Runs the one deferred capture once its earliest moment has arrived.
    ///
    /// Everything is re-checked against the state *now*: the key is still held,
    /// the generation is still current, the mode has not changed, the switch and
    /// the capture permission are still on, and the pointer is still on the same
    /// window it was on when the read failed. A capture is never taken of
    /// whatever moved into that position meanwhile, and a candidate that cannot
    /// be honoured is dropped rather than retried again — which is what keeps
    /// this bounded.
    private func retryDeferredOCRIfDue(now date: Date) {
        guard let pending = pendingOCR, date >= pending.notBefore else { return }
        pendingOCR = nil
        guard !ocrInFlight,
              isTriggerHeld,
              lifecycle.acceptsNewContent,
              gate.accepts(pending.generation),
              pending.request.mode == activeMode,
              let ocr = ocrFallback,
              OCRFallbackPolicy.allows(pending.failure,
                                       userEnabled: settings.isOCRFallbackEnabled,
                                       captureAuthorized: captureAuthorized(),
                                       sourceConfirmed: true),
              stillOnTheSameSource(pending.request),
              ocrLimiter.takeSlot(now: date) else {
            log.debug("deferred capture was dropped")
            return
        }
        log.debug("deferred capture starting")
        startOCR(ocr, request: pending.request, generation: pending.generation)
    }

    /// The pointer must still be inside the stable radius of the position that
    /// failed, and the window under it must still be the same owned window.
    private func stillOnTheSameSource(_ request: ExtractionRequest) -> Bool {
        let point = pointerLocation()
        guard hypot(point.x - request.point.x, point.y - request.point.y) <= dwell.radius else { return false }
        guard let source = locator.currentSource(at: point),
              source.pid == request.sourcePID,
              source.windowID == request.sourceWindowID,
              let bundleID = source.bundleID, !bundleID.isEmpty else { return false }
        return SourcePolicy(excludedBundleIDs: settings.excludedBundleIDs).allows(bundleID: bundleID)
    }

    // MARK: - Status

    /// A short status line for something that is not a result. The same text is
    /// throttled, so moving the pointer across blank space cannot produce a
    /// stream of identical lines, and a pinned card is never covered by one.
    private func showStatus(_ text: String, at point: CGPoint) {
        guard lifecycle.phase != .pinned else { return }
        let date = now()
        if let lastStatus, lastStatus.text == text,
           date.timeIntervalSince(lastStatus.shownAt) < Self.statusThrottle { return }
        lastStatus = (text, date)
        statusUntil = date.addingTimeInterval(Self.statusDuration)
        // A category only: the text comes from this app's own failure messages.
        log.debug("status shown")
        presenter.showStatus(text, at: point)
        startTickingIfNeeded()
    }

    private func dismissStatus() {
        statusUntil = nil
        presenter.dismissStatus()
    }

    private func dismissStatusIfDue(now date: Date) {
        guard let statusUntil, date >= statusUntil else { return }
        self.statusUntil = nil
        presenter.dismissStatus()
    }

    /// Puts a snapshot on the card and starts translating it.
    private func show(_ snapshot: ExtractionSnapshot, generation: UInt64) {
        shownSnapshot = snapshot
        lastScope = snapshot.scope
        lastFailure = nil
        lastTranslationText = nil
        lastTranslationFailure = nil
        presenter.present(snapshot)
        requestDictionaryEntry(for: snapshot, generation: generation)
        requestTranslation(for: snapshot, generation: generation)
    }

    /// Asks the wordbook for the meanings of a single word.
    ///
    /// The wordbook is a local file — no key, no permission, no network — and the
    /// word is one the app already read. The lookup runs off the main actor, and
    /// its answer is dropped unless the card still shows the same generation, so
    /// a late answer can never land on newer text.
    private func requestDictionaryEntry(for snapshot: ExtractionSnapshot, generation: UInt64) {
        guard snapshot.scope == .word, let senseProvider else { return }
        // Category only: never the word itself.
        log.debug("dictionary asked")
        dictionaryTask?.cancel()
        dictionaryTask = Task { [weak self] in
            let entry = await senseProvider.entry(for: snapshot.text)
            guard let self, !Task.isCancelled, let entry,
                  self.shownSnapshot?.generation == generation else {
                self?.log.debug("dictionary outcome=miss")
                return
            }
            self.log.debug("dictionary outcome=hit")
            self.presenter.setDictionary(entry, for: snapshot)
        }
    }

    /// A failed extraction: the card goes away and the reason is kept for the menu.
    private func report(failure: ExtractionFailure) {
        shownSnapshot = nil
        lastScope = nil
        lastTranslationText = nil
        lastTranslationFailure = nil
        lastFailure = failure
        // The category only, so a session can tell "nothing was read" from
        // "the control cannot report positions" without any user text.
        log.debug("extraction failed reason=\(failure.rawValue, privacy: .public)")
        presenter.dismiss()
        lifecycle.dismiss()
        // A failure that shows nothing at all reads as "the app stopped working".
        // The reason stays on the menu as well.
        showStatus(failure.message, at: pointerLocation())
    }

    /// v0.3 task 3: one timing record per stage and request.
    ///
    /// A stage name, a generation, a duration in milliseconds and an outcome
    /// category only. Never the text, the translation, an image, a window title
    /// or a file path.
    private func logTiming(stage: String, generation: UInt64, startedAt: Date, outcome: String) {
        let milliseconds = Int(now().timeIntervalSince(startedAt) * 1000)
        log.debug("stage=\(stage, privacy: .public) gen=\(generation, privacy: .public) ms=\(milliseconds, privacy: .public) outcome=\(outcome, privacy: .public)")
    }

    private func cancelOutstanding(hideCard: Bool) {
        gate.invalidate()
        task?.cancel()
        task = nil
        translationTask?.cancel()
        translationTask = nil
        dictionaryTask?.cancel()
        dictionaryTask = nil
        pendingOCR = nil
        dismissStatus()
        shownSnapshot = nil
        lastTranslationText = nil
        lastTranslationFailure = nil
        guard hideCard, lifecycle.phase != .pinned else { return }
        let wasVisible = lifecycle.isVisible
        lifecycle.dismiss()
        guard wasVisible else { return }
        presenter.dismiss()
        presenter.setPinned(false)
    }

    // MARK: - Translation

    /// Starts translating what is on the card, if a provider is configured.
    ///
    /// The extraction generation is the request identity too: a translation that
    /// finishes after the card moved on is dropped by the same gate that drops
    /// late extractions. A missing key is not an error state that hides the
    /// original text — it is reported as an actionable hint.
    private func requestTranslation(for snapshot: ExtractionSnapshot, generation: UInt64) {
        guard lifecycle.phase != .pinned else { return }
        guard settings.isEnabled, let translation else { return }
        let configuration = translation.configuration()
        guard configuration.isConfigured else {
            lastTranslationFailure = .apiKeyMissing
            presenter.setTranslationFailure(.apiKeyMissing, for: snapshot)
            return
        }
        let text = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = TranslationRequest(text: text,
                                         context: snapshot.context ?? "",
                                         mode: snapshot.mode)
        let key = cacheKey(for: request, model: configuration.model)
        let model = configuration.model
        let sourceBundleID = snapshot.sourceBundleID
        let apiKey = configuration.apiKey

        // The previous task is not cancelled here: it is already invalidated by
        // the generation, and cancelling it would also cancel a cache lookup
        // that the newest session is about to need.
        let startedAt = now()
        translationTask = Task { [weak self] in
            if let self,
               let hit = await self.cachedAnswer(for: key, generation: generation, sourceBundleID: sourceBundleID) {
                self.translationTask = nil
                self.lastTranslationText = hit.text
                self.lastTranslationFailure = nil
                self.logTiming(stage: "cache", generation: generation, startedAt: startedAt, outcome: "hit")
                self.presenter.setTranslation(hit, for: snapshot)
                return
            }
            if Task.isCancelled { return }
            guard let self, self.gate.accepts(generation) else { return }
            self.translationStarts += 1
            self.presenter.setTranslating()
            do {
                let result = try await translation.service.translate(request, apiKey: apiKey, model: model)
                guard self.gate.accepts(generation) else { return }
                self.translationTask = nil
                self.lastTranslationText = result.text
                self.lastTranslationFailure = nil
                self.logTiming(stage: "translation", generation: generation, startedAt: startedAt, outcome: "success")
                self.presenter.setTranslation(result, for: snapshot)
                if let cache = translation.cache {
                    await cache.insert(result, for: key, sourceBundleID: sourceBundleID)
                }
            } catch {
                guard self.gate.accepts(generation) else { return }
                self.translationTask = nil
                let failure = (error as? TranslationFailure) ?? .network
                self.lastTranslationFailure = failure
                self.logTiming(stage: "translation", generation: generation, startedAt: startedAt, outcome: failure.rawValue)
                self.presenter.setTranslationFailure(failure, for: snapshot)
            }
        }
    }

    // MARK: - v0.4 explanation

    /// Explains what is on the card, and only because the user pressed Explain.
    ///
    /// The button only exists on a card that is already interactive (released or
    /// pinned), so an automatic hover never reaches here. The explanation reuses
    /// the configured model and key, the same cache and the same failure mapping
    /// as a translation, but it is a different request: a different mode, a
    /// different prompt and a different output cap.
    func explainDisplayedText() {
        guard lifecycle.phase == .frozen || lifecycle.phase == .pinned else { return }
        guard let snapshot = shownSnapshot else { return }
        guard settings.isEnabled, let translation else {
            lastExplanationFailure = .configuration
            presenter.setExplanationFailure(.configuration, for: snapshot)
            return
        }
        let configuration = translation.configuration()
        guard configuration.isConfigured else {
            lastExplanationFailure = .apiKeyMissing
            presenter.setExplanationFailure(.apiKeyMissing, for: snapshot)
            return
        }
        let request = TranslationRequest(text: snapshot.text,
                                         context: snapshot.context ?? "",
                                         mode: ExplanationRequestBuilder.mode)
        let key = cacheKey(for: request, model: configuration.model)
        let model = configuration.model
        let apiKey = configuration.apiKey
        let sourceBundleID = snapshot.sourceBundleID

        // A fresh generation: whatever the hover left in flight is stale, and an
        // answer that arrives after the card moved on must not be shown.
        let generation = gate.begin()
        presenter.setExplanationLoading()
        let startedAt = now()
        explanationTask = Task { [weak self] in
            if let self,
               let hit = await self.cachedAnswer(for: key, generation: generation, sourceBundleID: sourceBundleID) {
                self.explanationTask = nil
                self.lastExplanationText = hit.text
                self.lastExplanationFailure = nil
                self.logTiming(stage: "cache", generation: generation, startedAt: startedAt, outcome: "hit")
                self.presenter.setExplanation(hit.text, for: snapshot)
                return
            }
            if Task.isCancelled { return }
            guard let self, self.gate.accepts(generation) else { return }
            self.explanationStarts += 1
            do {
                let result = try await translation.service.translate(request, apiKey: apiKey, model: model)
                guard self.gate.accepts(generation) else { return }
                self.explanationTask = nil
                self.lastExplanationText = result.text
                self.lastExplanationFailure = nil
                self.logTiming(stage: "explanation", generation: generation, startedAt: startedAt, outcome: "success")
                self.presenter.setExplanation(result.text, for: snapshot)
                if let cache = translation.cache {
                    await cache.insert(result, for: key, sourceBundleID: sourceBundleID)
                }
            } catch {
                guard self.gate.accepts(generation) else { return }
                self.explanationTask = nil
                let failure = (error as? TranslationFailure) ?? .network
                self.lastExplanationFailure = failure
                self.logTiming(stage: "explanation", generation: generation, startedAt: startedAt, outcome: failure.rawValue)
                self.presenter.setExplanationFailure(failure, for: snapshot)
            }
        }
    }

    /// A cache hit costs nothing and must be checked before the card claims to
    /// be in flight.
    ///
    /// Returns nil on a miss, on a source the user has now excluded, or when the
    /// generation was superseded — the same gate that drops late answers also
    /// refuses to reuse an answer for a request that moved on.
    private func cachedAnswer(for key: CacheKey,
                              generation: UInt64,
                              sourceBundleID: String?) async -> TranslationResult? {
        guard let cache = translation?.cache,
              let hit = await cache.get(key,
                                        sourceBundleID: sourceBundleID,
                                        excludedBundleIDs: settings.excludedBundleIDs),
              gate.accepts(generation) else { return nil }
        cacheHits += 1
        return hit
    }

    private var translationTask: Task<Void, Never>?

    // MARK: - Copy and manual entry

    /// Only ever writes to the clipboard when the user clicks Copy on the card.
    func copyDisplayedText() {
        guard shownSnapshot != nil else { return }
        presenter.copyDisplayedText()
    }

    /// Only ever called from the Copy button of the manual window.
    func copyManualResult() {
        manualPresenter?.copyDisplayedText()
    }

    /// The selection shortcut was pressed.
    ///
    /// The source is the application that owns the focused control, resolved
    /// from the element's own PID — never the window under the pointer. The
    /// source policy is applied *before* the selection body is read, and again
    /// after the read and before anything is sent, so an application the user
    /// excluded (or focused meanwhile) contributes no text and no request.
    func handleSelectionRequest() {
        guard settings.isEnabled else { return }
        // The selection action never involves the hover card: it is the user's
        // own text, not something under the pointer.
        cancelOutstanding(hideCard: true)
        let generation = gate.begin()
        Task { [weak self] in
            guard let self else { return }
            guard let focus = await self.selectionReader.focusedControl() else {
                guard self.gate.accepts(generation) else { return }
                self.promptForManualPaste(nil)
                return
            }
            guard self.gate.accepts(generation) else { return }
            self.confirmSelectionSource(focus, generation: generation)
        }
    }

    /// Step two: the focused control is known, its text is not. Only an
    /// attributable, non-excluded, non-protected source goes on to a read.
    private func confirmSelectionSource(_ focus: SelectionFocus, generation: UInt64) {
        let bundleID = bundleIdentifierForPID(focus.pid)
        guard let bundleID, !bundleID.isEmpty else {
            promptForManualPaste(.unknownOwner)
            return
        }
        guard SourcePolicy(excludedBundleIDs: settings.excludedBundleIDs).allows(bundleID: bundleID) else {
            promptForManualPaste(.appNotAllowed)
            return
        }
        guard !focus.isSecure else {
            promptForManualPaste(.blockedSensitive)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let text = await self.selectionReader.selectedText(belongingTo: focus.pid)
            // The rules may have changed while the read was in flight, and the
            // focus may have moved. A selection that is no longer allowed is
            // never sent.
            guard self.gate.accepts(generation),
                  SourcePolicy(excludedBundleIDs: self.settings.excludedBundleIDs).allows(bundleID: bundleID) else { return }
            self.routeSelectionText(text, source: SourceApp(pid: focus.pid, bundleID: bundleID))
        }
    }

    /// Step three: a source-confirmed selection, routed exactly as the entry
    /// point did before the source became part of the decision.
    private func routeSelectionText(_ text: String?, source: SourceApp) {
        lastSelectionSource = source.bundleID
        let usable = text.flatMap { candidate -> String? in
            TextInputPolicy.isAllowed(candidate, limit: TextInputPolicy.defaultLimit) ? candidate : nil
        }
        guard let usable else {
            // Nothing readable: the user pastes it themselves.
            promptForManualPaste(nil)
            return
        }
        let configuration = translation?.configuration()
        guard let configuration, configuration.isConfigured else {
            lastTranslationFailure = .apiKeyMissing
            manualPresenter?.showManualInput(usable, failure: .apiKeyMissing)
            revealManualWindow?()
            return
        }
        // The text is already known, so the window shows it and the request goes
        // out immediately. The user can still edit and re-send.
        manualPresenter?.showManualInput(usable, failure: nil)
        revealManualWindow?()
        submitManualText(usable)
    }

    /// An empty editor plus the reason, when there is one. Used by every path
    /// where nothing could be read, and by the menu entry.
    private func promptForManualPaste(_ reason: ExtractionFailure?) {
        lastSelectionSource = nil
        manualPresenter?.promptForManualPaste(reason)
        revealManualWindow?()
    }

    /// The menu's "Translate Selected or Pasted Text…" entry: an empty editor
    /// and a hint. The clipboard is never read here.
    func openManualEntry() {
        promptForManualPaste(nil)
    }

    private(set) var lastSelectionSource: String?

    private func cacheKey(for request: TranslationRequest, model: String) -> CacheKey {
        CacheKey(mode: request.mode,
                 text: request.text,
                 context: request.context,
                 targetLanguage: request.targetLanguage,
                 provider: "deepseek",
                 model: model)
    }

    func attachManualPresenter(_ presenter: ManualPresenting) {
        manualPresenter = presenter
    }

    /// The user pressed Translate in the manual window: exactly what is in the
    /// editor is sent, after the length policy check. Nothing here writes or
    /// restores the clipboard.
    func submitManualText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TextInputPolicy.isAllowed(trimmed, limit: TextInputPolicy.defaultLimit) else {
            lastTranslationFailure = .configuration
            manualPresenter?.showManualInput(text, failure: .configuration)
            return
        }
        guard settings.isEnabled, let translation, let manualPresenter else { return }
        let configuration = translation.configuration()
        guard configuration.isConfigured else {
            lastTranslationFailure = .apiKeyMissing
            manualPresenter.showManualInput(text, failure: .apiKeyMissing)
            return
        }
        let request = TranslationRequest(text: trimmed, mode: .selection)
        let key = cacheKey(for: request, model: configuration.model)
        let model = configuration.model
        let apiKey = configuration.apiKey

        // A fresh generation invalidates any hover request that was still in
        // flight; the manual window has its own presenter, so nothing displayed
        // there can be overwritten by an older answer.
        let generation = gate.begin()
        translationTask = Task { [weak self] in
            if let self, let hit = await self.cachedAnswer(for: key, generation: generation, sourceBundleID: nil) {
                self.translationTask = nil
                self.lastTranslationText = hit.text
                self.lastTranslationFailure = nil
                manualPresenter.setManualResult(hit.text, snapshotText: trimmed)
                return
            }
            if Task.isCancelled { return }
            guard let self, self.gate.accepts(generation) else { return }
            self.translationStarts += 1
            do {
                let result = try await translation.service.translate(request, apiKey: apiKey, model: model)
                guard self.gate.accepts(generation) else { return }
                self.translationTask = nil
                self.lastTranslationText = result.text
                self.lastTranslationFailure = nil
                manualPresenter.setManualResult(result.text, snapshotText: trimmed)
                if let cache = translation.cache {
                    await cache.insert(result, for: key, sourceBundleID: nil)
                }
            } catch {
                guard self.gate.accepts(generation) else { return }
                self.translationTask = nil
                let failure = (error as? TranslationFailure) ?? .network
                self.lastTranslationFailure = failure
                manualPresenter.showManualInput(trimmed, failure: failure)
            }
        }
    }

    // MARK: - v0.4 saved entries

    /// Saves what is on the card, and only because the user pressed Save.
    ///
    /// A normal hover, a cache hit and a pinned card never save anything on
    /// their own. Anything the store cannot write is reported on the card
    /// instead of being swallowed.
    func saveDisplayedText() {
        guard let snapshot = shownSnapshot else { return }
        guard let translation = lastTranslationText else {
            presenter.showNote("translate first — there is nothing to save yet")
            return
        }
        let entry = SavedEntry(source: snapshot.text,
                               translation: translation,
                               context: snapshot.context ?? "")
        do {
            try learning.save(entry)
            presenter.showNote("saved to your saved entries")
            didSaveEntry?()
        } catch {
            // Never the file contents: only that the write was refused.
            log.debug("a saved entry could not be written")
            presenter.showNote("saved entries could not be read, so nothing was written; clear them in Settings first")
        }
    }

    /// The settings action. The cache is an actor, so this waits for the real
    /// clear and reports how many answers were dropped.
    @discardableResult
    func clearTranslationCache() async -> Int? {
        // Clearing first and asking questions later would let an answer that is
        // already in flight write itself straight back in.
        invalidateInFlightRequests()
        guard let cache = translation?.cache else { return nil }
        let before = await cache.count
        await cache.removeAll()
        cacheHits = 0
        return before
    }

    /// Called when the exclusion list changes: a cached answer for a source that
    /// is now excluded must not survive, and neither may an answer that is
    /// already in flight under the old rules.
    func translationPolicyChanged() {
        invalidateInFlightRequests()
        guard let cache = translation?.cache else { return }
        let excluded = settings.excludedBundleIDs
        Task { await cache.removeAll(sourcesExcludedBy: excluded) }
    }

    /// Called when the API key is saved or deleted: nothing may be reused.
    func translationCredentialsChanged() {
        invalidateInFlightRequests()
        guard let cache = translation?.cache else { return }
        Task { await cache.removeAll() }
    }

    /// The screen locked or the session ended. The design requires the cache to
    /// be dropped here; the in-flight requests are invalidated first, so a late
    /// answer can neither be shown nor written back afterwards.
    func sessionWentInactive() {
        invalidateInFlightRequests()
        dwell.reset()
        stopTickingIfIdle()
        guard let cache = translation?.cache else { return }
        Task { await cache.removeAll() }
    }

    /// Called when the user turns cloud translation off. Whatever is in flight
    /// was started under the old decision and must not land, and the cached
    /// answers go with it (design §8).
    func translationDisabled() {
        invalidateInFlightRequests()
        guard let cache = translation?.cache else { return }
        Task { await cache.removeAll() }
    }

    /// Drops everything that is still in flight without touching the cache: the
    /// caller decides what to clear, and does it after this. A pinned card keeps
    /// its already-shown content, but never an active request.
    private func invalidateInFlightRequests() {
        cancelOutstanding(hideCard: true)
        explanationTask?.cancel()
        explanationTask = nil
    }

    // MARK: - Ticking

    private var needsTicking: Bool {
        isTriggerHeld || lifecycle.hasPendingClose || pendingOCR != nil || statusUntil != nil
    }

    private func startTickingIfNeeded() {
        guard !isTicking, needsTicking else { return }
        isTicking = true
        scheduler.startTicking(interval: 0.05) { [weak self] date in
            self?.tick(now: date)
        }
    }

    private func stopTickingIfIdle() {
        guard isTicking, !needsTicking else { return }
        isTicking = false
        scheduler.stopTicking()
    }
}
