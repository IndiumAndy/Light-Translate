import AppKit
import SwiftUI

/// Non-activating, click-through result card.
///
/// While the trigger key is held the panel ignores mouse events and shows no
/// buttons. After release it becomes interactive and the buttons appear. The
/// panel is never made key for a hover result and the app is never activated
/// for it; only the manual-entry view asks to become key, because the user has
/// to be able to paste into it.
@MainActor
final class FloatingPanelController: CardPresenting {
    let actions: CardActions

    private let model: CardViewModel
    private let hosting: NSHostingView<TranslationCard>
    private let panel: NSPanel
    private var lastHit: CGRect?
    private var displayedText = ""
    private var translationText: String?

    init() {
        let model = CardViewModel()
        let actions = CardActions()
        let hosting = NSHostingView(rootView: TranslationCard(model: model, actions: actions))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 80),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        // Window levels take precedence over orderFrontRegardless(). A normal
        // floating panel (3) stays behind an open menu (101). Keep hover content
        // one level above popup menus, well below system/security overlays.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = hosting

        self.model = model
        self.actions = actions
        self.hosting = hosting
        self.panel = panel
    }

    // MARK: - CardPresenting

    func present(_ snapshot: ExtractionSnapshot) {
        model.sessionID = snapshot.generation
        model.original = snapshot.text
        model.translation = nil
        model.translationFailure = nil
        model.dictionary = nil
        model.explanation = nil
        model.explanationFailure = nil
        model.explanationLoading = false
        model.note = nil
        model.statusText = nil
        model.manualVisible = false
        model.manualText = ""
        model.manualFailure = nil
        model.caption = caption(for: snapshot)
        model.buttonsVisible = false
        model.pinned = false
        displayedText = snapshot.text
        translationText = nil
        lastHit = snapshot.wordFrame
        panel.ignoresMouseEvents = true
        resizeAndPlace()
        panel.orderFrontRegardless()
    }

    func setTranslating() {
        model.translationFailure = nil
        resizeAndPlace()
    }

    func setTranslation(_ result: TranslationResult, for snapshot: ExtractionSnapshot) {
        guard model.sessionID == snapshot.generation else { return }
        model.translation = result.text
        model.translationFailure = nil
        translationText = result.text
        resizeAndPlace()
    }

    func setTranslationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot) {
        guard model.sessionID == snapshot.generation else { return }
        model.translationFailure = failure.message
        resizeAndPlace()
    }

    /// The offline meanings for the word on the card. They arrive on their own, so
    /// a slow wordbook never delays the English or the translation.
    func setDictionary(_ entry: WordEntry, for snapshot: ExtractionSnapshot) {
        guard model.sessionID == snapshot.generation else { return }
        model.dictionary = entry
        resizeAndPlace()
    }

    // MARK: - v0.4 explanation and notes

    func setExplanationLoading() {
        model.explanationLoading = true
        model.explanationFailure = nil
        resizeAndPlace()
    }

    func setExplanation(_ text: String, for snapshot: ExtractionSnapshot) {
        guard model.sessionID == snapshot.generation else { return }
        model.explanationLoading = false
        model.explanation = text
        model.explanationFailure = nil
        resizeAndPlace()
    }

    func setExplanationFailure(_ failure: TranslationFailure, for snapshot: ExtractionSnapshot) {
        guard model.sessionID == snapshot.generation else { return }
        model.explanationLoading = false
        model.explanationFailure = failure.message
        resizeAndPlace()
    }

    func showNote(_ note: String) {
        model.note = note
        resizeAndPlace()
    }

    /// A status line is not a result: no source text, no buttons, still
    /// click-through, and never shown over a pinned card.
    ///
    /// It is placed like a result — above or below the point, never on it — so the
    /// pointer stays outside the panel. A status under the cursor would block the
    /// next hover on the very text the user is moving to.
    func showStatus(_ text: String, at point: CGPoint) {
        guard !model.pinned else { return }
        model.sessionID = 0
        model.statusText = text
        model.original = ""
        model.translation = nil
        model.translationFailure = nil
        model.dictionary = nil
        model.explanation = nil
        model.explanationFailure = nil
        model.explanationLoading = false
        model.note = nil
        model.caption = ""
        model.buttonsVisible = false
        displayedText = ""
        translationText = nil
        lastHit = CGRect(origin: point, size: .zero)
        panel.ignoresMouseEvents = true
        resizeAndPlace()
        panel.orderFrontRegardless()
    }

    func dismissStatus() {
        guard model.statusText != nil else { return }
        model.statusText = nil
        panel.orderOut(nil)
    }

    /// Writes the clipboard only when the user has clicked Copy.
    func copyDisplayedText() {
        let text = translationText ?? displayedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func setButtonsVisible(_ visible: Bool) {
        model.buttonsVisible = visible
        if visible { resizeAndPlace() }
    }

    func setInteractive(_ interactive: Bool) {
        panel.ignoresMouseEvents = !interactive
    }

    func setPinned(_ pinned: Bool) {
        model.pinned = pinned
    }

    func dismiss() {
        panel.orderOut(nil)
        model.pinned = false
        model.buttonsVisible = false
        model.explanation = nil
        model.explanationFailure = nil
        model.explanationLoading = false
        model.note = nil
        model.statusText = nil
        model.manualVisible = false
        model.manualText = ""
        model.manualFailure = nil
        lastHit = nil
        displayedText = ""
        translationText = nil
    }

    func containsScreenPoint(_ point: CGPoint) -> Bool {
        panel.isVisible && panel.frame.contains(point)
    }

    // MARK: - Placement

    private func resizeAndPlace() {
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width <= 0 || size.height <= 0 {
            size = CGSize(width: 340, height: 80)
        }
        panel.setContentSize(size)
        place(size: size)
    }

    private func place(size: CGSize) {
        let hit = lastHit ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let anchor = CGPoint(x: hit.midX, y: hit.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        panel.setFrame(CoordinateMapper.cardRect(size: size, hit: hit, visible: screen.visibleFrame),
                       display: true)
    }

    /// The caption names what was read and how much of it, so the panel never
    /// claims more than the local snapshot actually contains. The English above
    /// it is that exact range; the model never restates the source.
    private func caption(for snapshot: ExtractionSnapshot) -> String {
        var parts: [String]
        switch snapshot.scope {
        case .word: parts = ["word"]
        case .label: parts = ["label", "whole control"]
        case .sentence: parts = ["sentence", "\(snapshot.text.count) characters"]
        case .selection: parts = ["selection"]
        }
        switch snapshot.source {
        case .accessibility: parts.append("accessibility")
        case .ocr: parts.append("ocr")
        case .manual: parts.append("manual")
        }
        if snapshot.completeness == .partial {
            parts.append("partial — select the full sentence to translate all of it")
        }
        return parts.joined(separator: " · ")
    }
}
