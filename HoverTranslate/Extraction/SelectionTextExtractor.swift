import AppKit
import ApplicationServices
import Foundation

/// Which application and control currently owns the keyboard focus.
///
/// A value snapshot only: the Accessibility element never leaves the serial
/// queue, and the PID comes from the focused element itself. The window under
/// the pointer is deliberately not consulted — it is not the source of a
/// selection.
struct SelectionFocus: Equatable, Sendable {
    let pid: pid_t
    /// A password field, or a control whose role could not be read. Either way
    /// no text may be read from it.
    let isSecure: Bool
}

/// The selection entry's read, split in two on purpose: the caller confirms the
/// source between the two calls, so a refused application is never read.
protocol SelectionReading: Sendable {
    /// The control that owns the keyboard focus right now.
    func focusedControl() async -> SelectionFocus?
    /// The focused selection, but only while the focused control still belongs
    /// to `ownerPID`. A focus change during the read yields nil.
    func selectedText(belongingTo ownerPID: pid_t) async -> String?
}

/// Reads the focused control through Accessibility, once, for an explicit user
/// action.
///
/// It never touches the clipboard and never synthesises Command-C: if the
/// selection cannot be read, the caller opens the manual paste view instead.
struct SelectionTextExtractor: SelectionReading {
    struct Limits: Sendable {
        var messagingTimeout: Float = 0.5
        /// Matches the manual-entry limit so a selection cannot smuggle in more.
        var maximumLength: Int = TextInputPolicy.defaultLimit
    }

    private let queue = DispatchQueue(label: "com.atat.HoverTranslate.selection", qos: .userInitiated)
    private let limits: Limits

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    func focusedControl() async -> SelectionFocus? {
        let limits = self.limits
        return await onQueue { SelectionReader.focusedControl(limits: limits) }
    }

    func selectedText(belongingTo ownerPID: pid_t) async -> String? {
        let limits = self.limits
        return await onQueue { SelectionReader.selectedText(belongingTo: ownerPID, limits: limits) }
    }

    /// All Accessibility work stays on this one serial queue.
    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        let queue = self.queue
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }
}

private enum SelectionReader {
    static func focusedControl(limits: SelectionTextExtractor.Limits) -> SelectionFocus? {
        guard let element = focusedElement(limits: limits) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return SelectionFocus(pid: pid, isSecure: isSecure(element))
    }

    static func selectedText(belongingTo ownerPID: pid_t,
                             limits: SelectionTextExtractor.Limits) -> String? {
        guard let element = focusedElement(limits: limits) else { return nil }
        // The focused control may have changed while the source was confirmed.
        // Reading the new control would attribute one application's text to
        // another, so the read is refused instead.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == ownerPID else { return nil }
        return selectedText(of: element, limits: limits)
    }

    private static func focusedElement(limits: SelectionTextExtractor.Limits) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, limits.messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, limits.messagingTimeout)
        return element
    }

    /// A control this app cannot classify counts as protected, so the default is
    /// always to read nothing.
    private static func isSecure(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(element, kAXRoleAttribute as String) else { return true }
        // Secure text fields must never be read, even on an explicit action.
        return role.hasSuffix("SecureTextField")
    }

    private static func selectedText(of element: AXUIElement,
                                     limits: SelectionTextExtractor.Limits) -> String? {
        guard !isSecure(element) else { return nil }
        guard let text = stringAttribute(element, kAXSelectedTextAttribute as String) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= limits.maximumLength else { return nil }
        return trimmed
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }
}
