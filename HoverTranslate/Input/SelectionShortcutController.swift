import AppKit
import Carbon.HIToolbox
import Foundation
import os

/// The combinations the selection action may be bound to.
///
/// The app offers a fixed set instead of recording arbitrary keys, so a preset
/// carries its own label rather than the app guessing a character for a key
/// code it did not choose.
struct SelectionShortcut: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let label: String

    /// Index 0 is the design's initial value. The order is part of the stored
    /// preference, so new combinations are only ever appended.
    static let choices: [SelectionShortcut] = [
        SelectionShortcut(keyCode: 17, modifiers: [.control, .command], label: "Control-Command-T"),
        SelectionShortcut(keyCode: 1, modifiers: [.control, .command], label: "Control-Command-S"),
        SelectionShortcut(keyCode: 35, modifiers: [.control, .command], label: "Control-Command-P"),
        SelectionShortcut(keyCode: 17, modifiers: [.option, .command], label: "Option-Command-T"),
    ]

    static let `default` = choices[0]

    /// Falls back to the first preset for an out-of-range stored value.
    static func choice(at index: Int) -> SelectionShortcut {
        choices.indices.contains(index) ? choices[index] : .default
    }

    /// The modifier bits the public hot-key API takes. Carbon's own constants
    /// are used rather than a private bit pattern.
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

/// How the selection shortcut is registered right now.
enum SelectionRegistrationState: Equatable {
    /// Nothing has been registered yet.
    case idle
    /// The combination is registered; macOS delivers it once per press.
    case registered
    /// The system refused the combination because another application already
    /// owns it.
    case conflict
    /// The public hot-key API refused it for another reason.
    case failed(OSStatus)

    /// The one place this state becomes words, so the menu and Settings cannot
    /// describe the same registration two different ways.
    func summary(label: String, canReadSelection: Bool) -> String {
        switch self {
        case .idle:
            return "Selection shortcut \(label) is not registered yet."
        case .registered:
            return canReadSelection
                ? "Shortcut registered: \(label)."
                : "Shortcut registered: \(label). Accessibility permission is required to read the selection."
        case .conflict:
            return "\(label) is already used by another application. Pick another combination in Settings."
        case .failed:
            return "\(label) could not be registered with the system."
        }
    }
}

/// The public hot-key API behind a seam, so registration, conflict reporting and
/// release are testable without a keyboard or a second application.
@MainActor
protocol HotKeyRegistering: AnyObject {
    /// Installs the one event handler and registers `shortcut`. The caller
    /// releases the previous combination with `unregister()` first. Returns the
    /// status of the registration itself (`noErr`, `eventHotKeyExistsErr`, …).
    func register(_ shortcut: SelectionShortcut, onPress: @escaping () -> Void) -> OSStatus
    /// Releases the combination and the handler. Safe when nothing is
    /// registered.
    func unregister()
}

/// `RegisterEventHotKey` is the public interface that can be told "no": a
/// combination another application registered is reported instead of silently
/// doing nothing. It is not a key monitor, so it never swallows ordinary keys.
///
/// What it cannot do: detect an application that watches the keyboard with its
/// own event monitor rather than registering a hot key. That limit is stated in
/// Settings and the user guide rather than papered over.
@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    /// 'HTSL'
    private static let signature: OSType = 0x4854_534C
    private static let identifier: UInt32 = 1

    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var onPress: (() -> Void)?

    func register(_ shortcut: SelectionShortcut, onPress: @escaping () -> Void) -> OSStatus {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(),
                                            carbonHotKeyHandler,
                                            1,
                                            &spec,
                                            Unmanaged.passUnretained(self).toOpaque(),
                                            &handler)
        guard installed == noErr else {
            handler = nil
            return installed
        }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &reference)
        hotKey = reference
        self.onPress = status == noErr ? onPress : nil
        return status
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
    }

    /// Runs on the main thread, from the Carbon event handler below.
    fileprivate func pressed() {
        onPress?()
    }
}

/// A Carbon callback cannot capture anything, so the registrar is reached
/// through the user data pointer.
private func carbonHotKeyHandler(_ callRef: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { registrar.pressed() }
    return noErr
}

/// Registers the explicit selection shortcut and reports what the system said
/// about it.
///
/// Success means the registration itself: the real proof that a selection was
/// translated is the user pressing the shortcut and seeing a result, which the
/// coordinator reports.
@MainActor
final class SelectionShortcutController {
    private weak var coordinator: TranslationCoordinator?
    private let registrar: HotKeyRegistering
    /// Read whenever the registration is installed, so changing the preset takes
    /// effect as soon as Settings re-registers it.
    private let shortcut: () -> SelectionShortcut

    private(set) var state: SelectionRegistrationState = .idle
    private let log = Logger(subsystem: "com.atat.HoverTranslate", category: "selection")

    /// Whether the selection text itself can be read. Independent of the
    /// registration: the hot-key API needs no Accessibility permission, the
    /// reading does.
    var canReadSelection: Bool { AXIsProcessTrusted() }

    init(coordinator: TranslationCoordinator,
         registrar: HotKeyRegistering? = nil,
         shortcut: @escaping () -> SelectionShortcut = { .default }) {
        self.coordinator = coordinator
        self.registrar = registrar ?? CarbonHotKeyRegistrar()
        self.shortcut = shortcut
    }

    var currentShortcut: SelectionShortcut { shortcut() }

    /// Registers the combination the user chose, releasing the previous one
    /// first. Called at launch and whenever the setting changes.
    func refreshRegistration() {
        let selected = shortcut()
        registrar.unregister()
        let status = registrar.register(selected) { [weak self] in self?.press() }
        state = Self.state(for: status)
        // The system's own answer is the only evidence that the combination was
        // accepted, so it is recorded. A preset label and a status number only;
        // no user text is involved.
        log.notice("selection shortcut \(selected.label, privacy: .public) status=\(status, privacy: .public)")
    }

    /// How a registration result is read. Pure, so the conflict case is testable
    /// without a real conflict.
    static func state(for status: OSStatus) -> SelectionRegistrationState {
        if status == noErr { return .registered }
        if status == eventHotKeyExistsErr { return .conflict }
        return .failed(status)
    }

    func stop() {
        registrar.unregister()
        state = .idle
    }

    private func press() {
        // One registration means one delivery per press; the coordinator's
        // generation then drops anything a newer action has superseded.
        coordinator?.handleSelectionRequest()
    }
}
