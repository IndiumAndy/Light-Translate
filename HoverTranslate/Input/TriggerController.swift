import AppKit
import Foundation

/// Translates AppKit events into coordinator calls.
///
/// It never consumes, replays or inspects typed characters: only Option key
/// transitions, pointer moves and "something else happened" signals are read.
@MainActor
final class TriggerController {
    /// True only while the trigger key can actually be observed.
    ///
    /// A global key monitor is created successfully even when this process is
    /// untrusted, and it starts delivering events as soon as permission is
    /// granted — measured on macOS 26.3: an app launched untrusted received
    /// Option events 12 s after the grant, without being relaunched. So the
    /// monitor handle alone is not evidence that key events arrive; trust is.
    var keyMonitorAvailable: Bool {
        keyMonitor != nil && AXIsProcessTrusted()
    }

    private weak var coordinator: TranslationCoordinator?
    private var keyMonitor: Any?
    private var pointerMonitor: Any?
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var leftOptionDown = false
    private var rightOptionDown = false
    private var controlDown = false

    private static let leftOptionKeyCode: UInt16 = 58
    private static let rightOptionKeyCode: UInt16 = 61
    private static let leftControlKeyCode: UInt16 = 59
    private static let rightControlKeyCode: UInt16 = 62

    init(coordinator: TranslationCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        stop()
        installKeyMonitor()
        installPointerMonitors()
        installObservers()
    }

    /// Called when the app becomes active again, because the user may have
    /// granted Accessibility permission in System Settings meanwhile.
    func installMonitorsIfNeeded() {
        installKeyMonitor()
    }

    func stop() {
        for monitor in [keyMonitor, pointerMonitor, localMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        pointerMonitor = nil
        localMonitor = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        leftOptionDown = false
        rightOptionDown = false
        controlDown = false
    }

    // MARK: - Monitors

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // Installed regardless of trust on purpose: the same monitor starts
        // delivering events once the user grants permission, with no relaunch.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyEvent(event) }
        }
    }

    /// Whether the menu may claim the trigger key is being observed.
    nonisolated static func isTriggerKeyObservable(trusted: Bool, hasMonitor: Bool) -> Bool {
        hasMonitor && trusted
    }

    /// Mouse monitoring does not need Accessibility permission, so pointer
    /// tracking keeps working even before permission is granted.
    private func installPointerMonitors() {
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved,
                                                                      .leftMouseDown,
                                                                      .rightMouseDown,
                                                                      .otherMouseDown,
                                                                      .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event) }
        }

        // Events delivered to this app are not seen by a global monitor.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved,
                                                                   .leftMouseDown,
                                                                   .rightMouseDown,
                                                                   .otherMouseDown,
                                                                   .scrollWheel,
                                                                   .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event) }
            return event
        }
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        // Switching application only invalidates the current hover.
        let hoverNames: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in hoverNames {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinator?.externalChange() }
            }
            observers.append(observer)
        }
        // The session locking or the screen sleeping ends the session, and the
        // cache goes with it (design §8). These two are deliberately not the
        // same event as switching application.
        let sessionNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in sessionNames {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinator?.sessionWentInactive() }
            }
            observers.append(observer)
        }
        let screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil,
                                                                    queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator?.externalChange() }
        }
        observers.append(screenObserver)
    }

    // MARK: - Event handling

    private func handleKeyEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            // Any ordinary key press cancels work that is not pinned.
            coordinator?.otherInput(at: NSEvent.mouseLocation)
            return
        }
        let optionDown = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case Self.leftOptionKeyCode:
            leftOptionDown.toggle()
        case Self.rightOptionKeyCode:
            rightOptionDown.toggle()
        case Self.leftControlKeyCode, Self.rightControlKeyCode:
            // Control is read from the modifier flags, never from characters,
            // and it only ever selects a mode; the event is never consumed.
            break
        default:
            // Another modifier changed: resynchronise when Option is not held.
            if !optionDown {
                leftOptionDown = false
                rightOptionDown = false
            }
            return
        }
        // A stale toggle cannot survive a state where no Option key is held.
        if !optionDown {
            leftOptionDown = false
            rightOptionDown = false
        }
        controlDown = event.modifierFlags.contains(.control)
        coordinator?.optionStateChanged(right: rightOptionDown, left: leftOptionDown, control: controlDown)
    }

    private func handlePointerEvent(_ event: NSEvent) {
        if event.type == .mouseMoved {
            coordinator?.pointerMoved(to: NSEvent.mouseLocation, at: Date())
        } else {
            coordinator?.otherInput(at: NSEvent.mouseLocation)
        }
    }
}
