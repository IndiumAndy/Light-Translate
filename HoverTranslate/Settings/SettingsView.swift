import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var translationSettings: TranslationSettingsStore
    let secrets: SecretStoring
    let coordinator: TranslationCoordinator
    /// The registered selection shortcut, so changing the preset re-registers
    /// it and the result can be reported here.
    let selection: SelectionShortcutController?
    @ObservedObject var learningModel: LearningModel
    let onGrantAccessibility: () -> Void
    let onRequestScreenRecording: () -> Void
    let hasScreenRecordingPermission: () -> Bool

    @State private var apiKeyField = ""
    @State private var registrationNote = ""
    @State private var keyStatus = ""
    @State private var connectionStatus: String?
    @State private var cacheStatus: String?
    @State private var isTesting = false
    @State private var captureAuthorized = false
    @State private var confirmingDeleteAll = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                extractionSection
                Divider()
                applicationsSection
                Divider()
                translationSection
                Divider()
                ocrSection
                Divider()
                learningSection
                Divider()
                permissionSection
            }
            .padding(20)
        }
        .frame(width: 480, height: 720)
        .onAppear {
            apiKeyField = secrets.secret(for: KeychainStore.deepSeekAPIKeyAccount) ?? ""
            keyStatus = apiKeyField.isEmpty ? "No key stored." : "A key is stored in the Keychain."
            captureAuthorized = hasScreenRecordingPermission()
            registrationNote = selectionNote
        }
    }

    /// v0.3: the screenshot fallback. Off by default, described plainly, and
    /// only offered together with the permission it needs.
    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screenshot fallback").font(.headline)
            Toggle("Read text from one screenshot when the application cannot report it", isOn: $store.isOCRFallbackEnabled)
                .onChange(of: store.isOCRFallbackEnabled) { _, enabled in
                    if enabled, !hasScreenRecordingPermission() {
                        onRequestScreenRecording()
                        captureAuthorized = hasScreenRecordingPermission()
                    }
                }

            HStack(spacing: 8) {
                Text(captureAuthorized ? "Screen Recording permission: granted" : "Screen Recording permission: not granted")
                    .font(.system(size: 11))
                Spacer()
                Button("Request…") {
                    onRequestScreenRecording()
                    captureAuthorized = hasScreenRecordingPermission()
                }
            }

            Text("Used only when Accessibility cannot locate the text at all, for an application you have not excluded, inside the window under the pointer. A frame stays in memory, is never written to disk, and is never uploaded. Screen Recording also lets any application capture the screen, so leave this off unless you want it.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var extractionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable hover extraction", isOn: $store.isEnabled)

            HStack(spacing: 12) {
                Text("Trigger key")
                Picker("", selection: $store.useRightOption) {
                    Text("Right Option").tag(true)
                    Text("Left Option").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack(spacing: 12) {
                Text("Selection shortcut")
                Picker("", selection: $store.selectionShortcutIndex) {
                    ForEach(SelectionShortcut.choices.indices, id: \.self) { index in
                        Text(SelectionShortcut.choices[index].label).tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .onChange(of: store.selectionShortcutIndex) { _, _ in
                    selection?.refreshRegistration()
                    registrationNote = selectionNote
                }
            }

            if !registrationNote.isEmpty {
                Text(registrationNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Hold the trigger key and rest the pointer on English text. Hold Control as well to read the whole sentence. Nothing is read before the pointer has rested for 250 ms.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("The selection shortcut works on text you have already selected in another application. It is registered with the system, so an application that already owns the combination is reported instead of failing silently. An application that watches the keyboard with its own event monitor cannot be detected, so a conflict with one of those would go unnoticed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every application is read; this list only ever narrows that down.
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applications").font(.headline)
            Text("Every application is read while you hold the trigger key. Add an application here only to exclude it — nothing is read from an excluded application, and password fields and other protected controls are never read in any application.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                if store.excludedBundleIDs.isEmpty {
                    Text("No applications excluded").foregroundStyle(.secondary)
                } else {
                    ForEach(store.excludedBundleIDs.sorted(), id: \.self) { identifier in
                        HStack {
                            Text(identifier).font(.system(size: 12))
                            Spacer()
                            Button("Include Again") {
                                store.stopExcluding(bundleID: identifier)
                                coordinator.translationPolicyChanged()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .frame(height: 110)
            .border(Color.primary.opacity(0.15))

            Button("Exclude Application…") { excludeApplication() }
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chinese translation").font(.headline)
            Toggle("Translate hovered words and selected text", isOn: $translationSettings.isTranslationEnabled)
                .onChange(of: translationSettings.isTranslationEnabled) { _, enabled in
                    // Turning translation off cancels what is in flight and
                    // drops the cached answers; turning it back on starts
                    // nothing by itself.
                    if !enabled { coordinator.translationDisabled() }
                }

            HStack(spacing: 8) {
                Text("Model")
                Picker("", selection: $translationSettings.model) {
                    ForEach(TranslationSettingsStore.knownModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Text("DeepSeek API key").font(.system(size: 12))
            SecureField("sk-…", text: $apiKeyField)
                .textFieldStyle(.roundedBorder)
            Text("The key is stored in this app's own Keychain item. It is never written to preferences, source, or logs.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Save key") { saveKey() }
                Button("Remove key") { removeKey() }
                Button(isTesting ? "Testing…" : "Test Connection") { testConnection() }
                    .disabled(isTesting || apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Button("Clear cached translations") { clearCache() }
                if let cacheStatus {
                    Text(cacheStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text("The cache is in memory only and is dropped when the app quits. Nothing is written to disk and no query history is kept.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !keyStatus.isEmpty {
                Text(keyStatus).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let connectionStatus {
                Text(connectionStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Test Connection sends only the synthetic text \"Open Settings\". It never sends anything from your screen.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// v0.4: saving never happens here — this only shows what the user saved,
    /// and gives the two ways to remove it.
    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved entries").font(.headline)
            Text("\(learningModel.entries.count) saved. Only entries you saved yourself are kept, in Application Support; no screenshot, window title or file path is stored.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = learningModel.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Open Saved Entries…") {
                    learningModel.reload()
                    openWindow(id: AppDelegate.learningWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                // Enabled for an unreadable file too: clearing it is the recovery.
                Button("Delete All…") { confirmingDeleteAll = true }
                    .disabled(learningModel.entries.isEmpty && learningModel.error == nil)
            }
        }
        .confirmationDialog("Delete every saved entry?",
                            isPresented: $confirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { learningModel.removeAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AXIsProcessTrusted() ? "Accessibility permission: granted" : "Accessibility permission: not granted")
                    .font(.system(size: 11))
                Spacer()
                Button("Grant…") { onGrantAccessibility() }
            }
            Text("macOS may require you to relaunch HoverTranslate after a permission change.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    /// What the system said about the current registration, in the same words
    /// the menu uses.
    private var selectionNote: String {
        guard let selection else { return "Selection shortcut is not registered." }
        return selection.state.summary(label: selection.currentShortcut.label,
                                       canReadSelection: selection.canReadSelection)
    }

    // MARK: - Key handling

    private func saveKey() {
        do {
            try secrets.setSecret(apiKeyField, for: KeychainStore.deepSeekAPIKeyAccount)
            // A different key means the cached answers were produced by an
            // identity that may no longer be in use.
            coordinator.translationCredentialsChanged()
            apiKeyField = secrets.secret(for: KeychainStore.deepSeekAPIKeyAccount) ?? ""
            keyStatus = apiKeyField.isEmpty ? "No key stored." : "Key saved to the Keychain."
            connectionStatus = nil
        } catch {
            keyStatus = "The key could not be saved to the Keychain."
        }
    }

    /// The settings action for the cache: it waits for the actor that owns the
    /// cache and reports how many answers were dropped, so "cleared" is a fact
    /// rather than a label.
    private func clearCache() {
        Task {
            let cleared = await coordinator.clearTranslationCache()
            cacheStatus = cleared.map { "Cleared \($0) cached answers." } ?? "No cache is in use."
        }
    }

    private func removeKey() {
        do {
            try secrets.setSecret(nil, for: KeychainStore.deepSeekAPIKeyAccount)
            coordinator.translationCredentialsChanged()
            apiKeyField = ""
            keyStatus = "Key removed from the Keychain."
            connectionStatus = nil
        } catch {
            keyStatus = "The key could not be removed from the Keychain."
        }
    }

    /// The only place a real request is ever started without a hover, and it
    /// sends a fixed synthetic string.
    private func testConnection() {
        let key = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isTesting = true
        connectionStatus = nil
        let service = DeepSeekTranslationService()
        Task {
            do {
                let result = try await service.translate(TranslationRequest(text: "Open Settings"),
                                                         apiKey: key,
                                                         model: translationSettings.model)
                connectionStatus = "Connection OK · model \(result.model) · synthetic text only"
            } catch let failure as TranslationFailure {
                connectionStatus = "Test failed: \(failure.message)"
            } catch {
                connectionStatus = "Test failed."
            }
            isTesting = false
        }
    }

    private func excludeApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !identifier.isEmpty else { return }
        store.exclude(bundleID: identifier)
        coordinator.translationPolicyChanged()
    }
}
