import AppKit
import Foundation

/// Presents manual-entry state in the manual window's own view model.
///
/// Deliberately not the floating panel: the hover card and the manual window
/// must never overwrite each other's content.
@MainActor
final class ManualWindowPresenter: ManualPresenting {
    private let model: CardViewModel

    init(model: CardViewModel) {
        self.model = model
    }

    func showManualInput(_ text: String?, failure: TranslationFailure?) {
        if let text { model.manualText = text }
        model.manualFailure = failure?.message
        model.translation = nil
    }

    /// An empty editor and the reason, when there is one. Nothing is read from
    /// the clipboard: if the user wants the selected text here, they paste it.
    func promptForManualPaste(_ reason: ExtractionFailure?) {
        model.manualText = ""
        model.original = ""
        model.translation = nil
        model.manualFailure = reason?.message
            ?? "Paste the text here, then press Translate. HoverTranslate never reads the clipboard by itself."
    }

    func setManualResult(_ translation: String, snapshotText: String) {
        model.original = snapshotText
        model.translation = translation
        model.manualFailure = nil
    }

    /// Only ever runs because the user clicked Copy.
    func copyDisplayedText() {
        let text = model.translation ?? model.manualText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
