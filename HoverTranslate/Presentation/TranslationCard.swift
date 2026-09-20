import AppKit
import SwiftUI

/// Presentation state of the floating card.
///
/// original is always the locally extracted text; translation is the only
/// model-produced string on screen, and it is never presented as the source.
@MainActor
final class CardViewModel: ObservableObject {
    /// Identifies the hover session this content belongs to, so a translation
    /// from a superseded session can never be written onto newer text.
    @Published var sessionID: UInt64 = 0
    @Published var original = ""
    @Published var translation: String?
    @Published var translationFailure: String?
    /// Parts of speech and several meanings of a single word, from the offline
    /// wordbook. Always labelled as a dictionary answer, never as a model's.
    @Published var dictionary: WordEntry?
    /// v0.4: only ever filled by an explicit Explain click, and always labelled
    /// as a model explanation rather than a dictionary entry.
    @Published var explanation: String?
    @Published var explanationFailure: String?
    @Published var explanationLoading = false
    /// A short status line (saved, nothing to save, saved list unreadable).
    @Published var note: String?
    /// A short status that replaces the whole card: a capture that is still
    /// waiting, or why nothing could be read here. Never a translation.
    @Published var statusText: String?
    @Published var caption = ""
    @Published var buttonsVisible = false
    @Published var pinned = false
    @Published var manualVisible = false
    @Published var manualText = ""
    @Published var manualFailure: String?
}

/// Holds the card actions so the panel can exist before the coordinator.
final class CardActions {
    var onCopy: (() -> Void)?
    var onPin: (() -> Void)?
    var onClose: (() -> Void)?
    /// v0.4: both only ever run because the user clicked the button.
    var onSave: (() -> Void)?
    var onExplain: (() -> Void)?
    /// Only the manual window uses this.
    var onTranslateManualText: ((String) -> Void)?
}

struct TranslationCard: View {
    @ObservedObject var model: CardViewModel
    let actions: CardActions

    var body: some View {
        content
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    /// A status is not a result: it replaces the whole card, because there is no
    /// source text to show and no buttons to offer.
    @ViewBuilder
    private var content: some View {
        if let status = model.statusText {
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            result
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.original)
                .font(.system(size: 15))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let dictionary = model.dictionary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictionary · On-device")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    ForEach(Array(dictionary.senses.enumerated()), id: \.offset) { _, sense in
                        Text(dictionaryLine(for: sense))
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if dictionary.truncated {
                        Text("…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let translation = model.translation {
                Text(translation)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = model.translationFailure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.explanationLoading {
                Text("explaining…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let explanation = model.explanation {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI explanation · not a dictionary entry")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(explanation)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let failure = model.explanationFailure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = model.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(model.caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if model.buttonsVisible {
                HStack(spacing: 8) {
                    Button("Copy") { actions.onCopy?() }
                    Button("Save") { actions.onSave?() }
                        .disabled(model.translation == nil)
                    Button("Explain") { actions.onExplain?() }
                    Button(model.pinned ? "Pinned" : "Pin") { actions.onPin?() }
                        .disabled(model.pinned)
                    Button("Close") { actions.onClose?() }
                }
                .controlSize(.small)
            }
        }
    }

    /// "n. 跑, 赛跑" — the part of speech in front of its meanings. A group whose
    /// part of speech the wordbook did not give shows the meanings alone.
    private func dictionaryLine(for sense: WordSense) -> String {
        let meanings = sense.glosses.joined(separator: ", ")
        return sense.partOfSpeech.isEmpty ? meanings : "\(sense.partOfSpeech) \(meanings)"
    }
}
