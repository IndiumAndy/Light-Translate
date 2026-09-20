import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let settingsWindowID = "settings"
    static let manualWindowID = "manual"
    static let learningWindowID = "learning"

    let settings = SettingsStore()
    let translationSettings = TranslationSettingsStore()
    let secrets = KeychainStore()
    /// The manual window owns its own card state, so it never fights the
    /// hovering card for content.
    let manualModel = CardViewModel()

    /// v0.4: the user's saved entries live in Application Support, never in a
    /// screenshot or a window title.
    let learningStore = LearningStore.applicationSupport()
    private(set) lazy var learningModel = LearningModel(store: learningStore)

    private lazy var panel = FloatingPanelController()

    private lazy var translationService = DeepSeekTranslationService()
    private lazy var translationCache = TranslationCache()

    /// Actions for the manual window, kept separate from the hovering card's.
    let manualActions = CardActions()

    /// Presents results in the manual window. Never touches the hover card.
    private lazy var manualPresenter = ManualWindowPresenter(model: manualModel)

    private(set) lazy var coordinator = TranslationCoordinator(
        extractor: AccessibilityTextExtractor(),
        presenter: panel,
        locator: PointerWindowSourceLocator(),
        settings: settings,
        translation: TranslationContext(
            service: translationService,
            cache: translationCache,
            configuration: { [translationSettings, secrets] in
                translationSettings.configuration(secrets: secrets)
            }),
        // v0.3: the screenshot fallback. The permission is only checked here,
        // never requested, so a refusal cannot turn into a prompt loop.
        // The bundled wordbook: parts of speech and several meanings for a
        // single word, offline and without a key.
        senses: BundledWordBookProvider(),
        ocrFallback: OCRTextExtractor(),
        captureAuthorized: { CGPreflightScreenCaptureAccess() },
        learning: learningStore)

    private(set) var triggerController: TriggerController?
    private(set) var selectionController: SelectionShortcutController?

    var cardActions: CardActions { panel.actions }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.actions.onPin = { [weak self] in self?.coordinator.pin() }
        panel.actions.onClose = { [weak self] in self?.coordinator.closeCard() }
        panel.actions.onCopy = { [weak self] in self?.coordinator.copyDisplayedText() }
        // Both of these only ever run from a click on an already interactive card.
        panel.actions.onSave = { [weak self] in self?.coordinator.saveDisplayedText() }
        panel.actions.onExplain = { [weak self] in self?.coordinator.explainDisplayedText() }
        // Saving does not go through this object, so it has to tell the open
        // saved-entries window to reload.
        coordinator.didSaveEntry = { [weak self] in self?.learningModel.reload() }
        manualModelActions()
        coordinator.attachManualPresenter(manualPresenter)
        // The selection shortcut's read is asynchronous: by the time it lands,
        // this window has to already be on screen. Bringing it forward never
        // reads the clipboard.
        coordinator.revealManualWindow = { [weak self] in
            self?.openManualWindow()
        }

        // The unit tests exercise pure logic only; they must not install global
        // event monitors or query Accessibility.
        guard !Self.isRunningTests else { return }

        let controller = TriggerController(coordinator: coordinator)
        controller.start()
        triggerController = controller

        let selection = SelectionShortcutController(
            coordinator: coordinator,
            shortcut: { [settings] in SelectionShortcut.choice(at: settings.selectionShortcutIndex) })
        selection.refreshRegistration()
        selectionController = selection
    }

    private func manualModelActions() {
        ManualActionWiring.wire(manualActions, coordinator: coordinator)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        triggerController?.installMonitorsIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        triggerController?.stop()
        selectionController?.stop()
    }

    /// Whether the screenshot fallback could actually run. Never prompts.
    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Only ever called from an explicit user action in settings, when the user
    /// turns the fallback on while the permission is missing.
    func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Only ever called from an explicit user action in the menu or settings.
    func grantAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Posted when the manual window must come to the front. The window itself
    /// is a SwiftUI `Window` scene, so opening it is the view layer's job; the
    /// AppKit event handler only asks for it.
    static let revealManualWindowNotification = Notification.Name("HoverTranslate.revealManualWindow")

    /// Brings the manual window to the front. It never touches the clipboard:
    /// the editor's content is always something the user pasted or typed, and
    /// the coordinator has already put the reason for the empty editor there.
    func openManualWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Self.revealManualWindowNotification, object: nil)
    }

    /// The menu's own entry point: it opens an empty editor with a hint, because
    /// the user may have selected text in an application that cannot be read.
    func openManualWindowFromMenu() {
        coordinator.openManualEntry()
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// The manual window's two buttons, wired in one place.
///
/// Copy belongs to the manual window's own result: it must never reach the
/// hovering card's snapshot, which may still hold a different text. Keeping the
/// wiring here is what lets a test prove that, instead of only testing the
/// coordinator's copy method.
@MainActor
enum ManualActionWiring {
    static func wire(_ actions: CardActions, coordinator: TranslationCoordinator) {
        actions.onTranslateManualText = { [weak coordinator] text in
            coordinator?.submitManualText(text)
        }
        actions.onCopy = { [weak coordinator] in
            coordinator?.copyManualResult()
        }
    }
}
