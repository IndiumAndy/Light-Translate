import SwiftUI

@main
struct HoverTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Light Translate", systemImage: "character.book.closed") {
            MenuContentView(store: delegate.settings,
                            translationSettings: delegate.translationSettings,
                            coordinator: delegate.coordinator,
                            trigger: delegate.triggerController,
                            selection: delegate.selectionController,
                            onGrantAccessibility: { delegate.grantAccessibilityPermission() },
                            onOpenManual: { delegate.openManualWindowFromMenu() })
        }

        Window("Light Translate Settings", id: AppDelegate.settingsWindowID) {
            SettingsView(store: delegate.settings,
                         translationSettings: delegate.translationSettings,
                         secrets: delegate.secrets,
                         coordinator: delegate.coordinator,
                         selection: delegate.selectionController,
                         learningModel: delegate.learningModel,
                         onGrantAccessibility: { delegate.grantAccessibilityPermission() },
                         onRequestScreenRecording: { delegate.requestScreenRecordingPermission() },
                         hasScreenRecordingPermission: { delegate.hasScreenRecordingPermission })
        }
        .windowResizability(.contentSize)

        Window("Translate text", id: AppDelegate.manualWindowID) {
            ManualTranslationView(model: delegate.manualModel, actions: delegate.manualActions)
        }
        .windowResizability(.contentSize)

        Window("Saved entries", id: AppDelegate.learningWindowID) {
            LearningView(model: delegate.learningModel)
        }
        .windowResizability(.contentSize)
    }
}
