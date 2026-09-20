import AppKit
import ApplicationServices
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var translationSettings: TranslationSettingsStore
    @ObservedObject var coordinator: TranslationCoordinator
    let trigger: TriggerController?
    let selection: SelectionShortcutController?
    let onGrantAccessibility: () -> Void
    let onOpenManual: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.revealManualWindowNotification)) { _ in
                openWindow(id: AppDelegate.manualWindowID)
            }
    }

    private var content: some View {
        Group {
        Toggle("Enable hover extraction", isOn: $store.isEnabled)

        Text(triggerLine)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        if !AXIsProcessTrusted() {
            Divider()
            Text("Accessibility permission is not granted, so the trigger key cannot be observed.")
                .font(.system(size: 11))
            Button("Grant Accessibility Access…") { onGrantAccessibility() }
        }

        Divider()
        Text(statusLine).font(.system(size: 11))

        Divider()
        // No menu key equivalent here on purpose: the real shortcut is
        // registered with the system and is user-configurable, so a fixed one
        // here would both mislead and risk firing the same request twice.
        Button("Translate Selected or Pasted Text…") {
            onOpenManual()
            openWindow(id: AppDelegate.manualWindowID)
        }

        Text(selectionLine)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

        Button("Saved Entries…") { openWindow(id: AppDelegate.learningWindowID) }

        if translationSettings.model.isEmpty || translationSettings.model != TranslationSettingsStore.defaultModel {
            Text("Model: \(translationSettings.model)").font(.system(size: 10)).foregroundStyle(.secondary)
        }

        Divider()
        Button("Open Settings…") {
            openWindow(id: AppDelegate.settingsWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Light Translate") { NSApp.terminate(nil) }
        }
    }

    private var triggerLine: String {
        guard let trigger, trigger.keyMonitorAvailable else {
            return "Trigger key is not being observed (Accessibility permission required)."
        }
        let key = store.useRightOption ? "Right Option" : "Left Option"
        return "Hold \(key) over English text. Hold Control as well for the whole sentence."
    }

    private var selectionLine: String {
        // The registration itself reports a conflict, so the menu can say what
        // the system said instead of only what the app can observe.
        let label = SelectionShortcut.choice(at: store.selectionShortcutIndex).label
        guard let selection else { return "Selection shortcut is not registered." }
        return selection.state.summary(label: label, canReadSelection: selection.canReadSelection)
    }

    private var statusLine: String {
        if let failure = coordinator.lastTranslationFailure {
            return "Translation: \(failure.message)"
        }
        if let translation = coordinator.lastTranslationText {
            return "Translation: \(translation)"
        }
        if let failure = coordinator.lastFailure {
            return "Last query: \(failure.message)"
        }
        if let scope = coordinator.lastScope {
            return "Last query: \(scope.rawValue)"
        }
        return "Last query: none"
    }
}
