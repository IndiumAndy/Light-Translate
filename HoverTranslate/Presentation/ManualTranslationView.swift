import AppKit
import SwiftUI

/// The manual entry point.
///
/// It is a real window rather than a state of the floating card so that the
/// user can type and paste with normal keyboard focus, while the hovering card
/// stays non-activating and never steals focus.
///
/// Nothing is read from the clipboard and nothing is sent until the user
/// presses Translate; the editor shows exactly what will be sent.
struct ManualTranslationView: View {
    @ObservedObject var model: CardViewModel
    let actions: CardActions

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translate English text")
                .font(.headline)
            Text("Paste or type the text, then press Translate. Nothing is sent before that.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.original.isEmpty, model.original != model.manualText {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected text (read locally, not sent as-is if you edit it)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(model.original)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextEditor(text: $model.manualText)
                .font(.system(size: 13))
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )

            Text("\(model.manualText.count) characters · maximum 4000")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if let failure = model.manualFailure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let translation = model.translation {
                Text(translation)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Translate") { actions.onTranslateManualText?(model.manualText) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Copy result") { actions.onCopy?() }
                    .disabled(model.translation == nil)
                Spacer()
                Button("Close") {
                    actions.onClose?()
                    dismiss()
                }
            }
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
