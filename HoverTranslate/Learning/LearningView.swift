import AppKit
import SwiftUI

/// v0.4: the saved-entries window's state.
///
/// Reading is the only thing that happens automatically. A file that cannot be
/// decoded is reported and left exactly as it is; clearing it is the user's
/// decision and the only operation that replaces it.
@MainActor
final class LearningModel: ObservableObject {
    @Published private(set) var entries: [SavedEntry] = []
    /// Set when the file could not be read; the file itself is untouched.
    @Published private(set) var error: String?

    private let store: LearningStore

    init(store: LearningStore = .applicationSupport()) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            entries = try store.all()
            error = nil
        } catch {
            // The caught error shadows the property by name, so be explicit.
            entries = []
            self.error = "The saved-entries file could not be read, so its contents are not shown. Nothing was changed or deleted."
        }
    }

    func remove(_ entry: SavedEntry) {
        try? store.remove(id: entry.id)
        reload()
    }

    func removeAll() {
        try? store.removeAll()
        reload()
    }
}

/// What the user chose to keep, and nothing else.
///
/// Normal hovers, cache hits and pinned cards never appear here: an entry only
/// exists because the Save button was pressed on a card.
struct LearningView: View {
    @ObservedObject var model: LearningModel
    @State private var confirmingDeleteAll = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved entries").font(.headline)
            Text("Only entries you saved yourself appear here. Nothing is saved automatically, and no screenshot, window title or file path is ever stored.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.entries.isEmpty {
                Text(model.error == nil ? "No saved entries yet." : "Nothing can be shown until the file is cleared.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                List {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.source)
                                    .font(.system(size: 13, weight: .medium))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Button("Delete") { model.remove(entry) }
                                    .controlSize(.small)
                            }
                            Text(entry.translation)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !entry.context.isEmpty {
                                Text("context: \(entry.context)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 220)
            }

            HStack(spacing: 8) {
                Text("\(model.entries.count) saved")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                // Enabled for an unreadable file too: clearing it is the recovery.
                Button("Delete All…") { confirmingDeleteAll = true }
                    .disabled(model.entries.isEmpty && model.error == nil)
                Button("Close") { dismiss() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 420)
        .confirmationDialog("Delete every saved entry?",
                            isPresented: $confirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { model.removeAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { model.reload() }
    }
}
