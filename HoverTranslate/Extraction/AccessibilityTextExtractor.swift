import ApplicationServices
import CoreGraphics
import Foundation
import os

/// A control the hit path may ask about, as an opaque token.
///
/// The token is a retained pointer owned by the AXControlReading that produced
/// it and handed back through release(_:) at the end of one read, so the object
/// lives exactly as long as the read that needs it. Only this value crosses the
/// boundary: no AXUIElement ever reaches the app.
struct AXControl: Equatable, Sendable {
    let token: UInt
}

/// The two facts that have to be true before any text may be read.
struct AXControlOwner: Equatable, Sendable {
    let pid: pid_t
    /// A password field, or a role that says so. Never upgraded to "readable".
    let isProtected: Bool
}

/// What a control reports for one screen position.
enum AXPositionMapping {
    /// A character range that covers the position.
    case resolved(CFRange)
    /// The control has no position-to-text mapping at all. This is the one
    /// technical limitation that may justify the OCR fallback; every policy
    /// failure is a different case and never does.
    case unsupported
    /// The call was accepted but produced no usable range.
    case none

    /// Content-free category, for the log only.
    var category: String {
        switch self {
        case .resolved: return "resolved"
        case .unsupported: return "unsupported"
        case .none: return "none"
        }
    }
}

/// Every Accessibility call the hit path makes, behind a seam.
///
/// The seam exists because the two position-carrying calls —
/// AXUIElementCopyElementAtPosition and AXRangeForPosition — both take screen
/// points whose origin is the top-left of the primary display, while the pointer
/// is tracked in AppKit coordinates. A test has to be able to see the exact
/// coordinates the reader hands over, and a synthetic control makes the whole
/// hit -> word/sentence/label decision testable without a running application.
protocol AXControlReading: Sendable {
    /// Whether this process may read other applications at all. Injected for the
    /// same reason the capture permission is: it is a policy input, and a test
    /// must be able to decide it without changing system state.
    func hasAccessibilityPermission() -> Bool
    /// The control under an AX screen point (origin at the top-left of the
    /// primary display). nil when nothing usable is there.
    func control(at point: CGPoint) -> AXControl?
    /// Releases a token handed out by control(at:).
    func release(_ control: AXControl)
    /// The control that currently has keyboard focus, whichever application owns
    /// it. The token is owned exactly like the one from control(at:) and is
    /// handed back through release(_). nil when the system reports no focused
    /// control at all.
    func focusedControl() -> AXControl?
    func owner(of control: AXControl) -> AXControlOwner?
    /// Classification only: never the text of the control.
    func role(of control: AXControl) -> String?
    /// The character count the control reports, when it reports one.
    func characterCount(of control: AXControl) -> Int?
    /// The control's own selected range, when it reports one. A control with no
    /// selection reports nil or a zero length.
    func selectedRange(of control: AXControl) -> CFRange?
    /// The text of the current selection, when the control reports it directly
    /// instead of through a range read.
    func selectedText(of control: AXControl) -> String?
    /// What the control reports for one AX point. Always the same converted
    /// point the hit was asked for.
    func range(at point: CGPoint, in control: AXControl) -> AXPositionMapping
    /// The text of one range, or nil when the control cannot read ranges.
    func text(of range: CFRange, in control: AXControl) -> String?
    /// The screen rect of one range, in AX coordinates.
    func bounds(of range: CFRange, in control: AXControl) -> CGRect?
    /// The control's own rect, in AX coordinates.
    func frame(of control: AXControl) -> CGRect?
    func title(of control: AXControl) -> String?
    func value(of control: AXControl) -> String?
    /// The control's own description attribute, when it reports one. Read only
    /// for a trusted short control, and never for a protected one.
    func description(of control: AXControl) -> String?
    /// The control's direct children, in the order the system reports them.
    /// Each token is owned exactly like the one from control(at:) and is handed
    /// back through release(_). Nothing below this one level is ever asked for.
    func children(of control: AXControl) -> [AXControl]
}

/// The real Accessibility calls.
///
/// Coordinates are AX coordinates (origin at the top-left of the primary
/// display); converting the pointer is the reader's job and happens exactly once.
struct SystemAXControls: AXControlReading {
    let messagingTimeout: Float

    func hasAccessibilityPermission() -> Bool { AXIsProcessTrusted() }

    func control(at point: CGPoint) -> AXControl? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system,
                                               Float(point.x),
                                               Float(point.y),
                                               &element) == .success,
              let element else { return nil }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AXControl(token: UInt(bitPattern: Unmanaged.passRetained(element).toOpaque()))
    }

    /// Balances the retain taken in control(at:). The token is the only owner
    /// between the two calls, so a read that forgets this leaks one object.
    func release(_ control: AXControl) {
        guard let pointer = pointer(of: control) else { return }
        Unmanaged<AXUIElement>.fromOpaque(pointer).release()
    }

    /// The focused control usually belongs to the frontmost application, which
    /// is not necessarily the application under the pointer: the caller compares
    /// the pid before reading anything from it.
    func focusedControl() -> AXControl? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AXControl(token: UInt(bitPattern: Unmanaged.passRetained(element).toOpaque()))
    }

    func owner(of control: AXControl) -> AXControlOwner? {
        guard let element = element(of: control) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return AXControlOwner(pid: pid, isProtected: isProtected(element))
    }

    func role(of control: AXControl) -> String? {
        guard let element = element(of: control) else { return nil }
        return stringAttribute(element, kAXRoleAttribute as String)
    }

    func characterCount(of control: AXControl) -> Int? {
        guard let element = element(of: control) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXNumberOfCharactersAttribute as CFString,
                                            &value) == .success,
              let value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        var count: CFIndex = 0
        guard CFNumberGetValue((value as! CFNumber), .cfIndexType, &count) else { return nil }
        return count
    }

    func selectedRange(of control: AXControl) -> CFRange? {
        guard let element = element(of: control) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextRangeAttribute as CFString,
                                            &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        return range
    }

    func selectedText(of control: AXControl) -> String? {
        guard let element = element(of: control) else { return nil }
        return stringAttribute(element, kAXSelectedTextAttribute as String)
    }

    func range(at point: CGPoint, in control: AXControl) -> AXPositionMapping {
        guard let element = element(of: control) else { return .none }
        var point = point
        guard let parameter = AXValueCreate(.cgPoint, &point) else { return .none }
        var raw: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element,
                                                               kAXRangeForPositionParameterizedAttribute as CFString,
                                                               parameter,
                                                               &raw)
        switch result {
        case .parameterizedAttributeUnsupported, .attributeUnsupported, .notImplemented:
            return .unsupported
        case .success:
            break
        default:
            return .none
        }
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return .none }
        var characterRange = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &characterRange),
              characterRange.location >= 0,
              characterRange.length > 0 else { return .none }
        return .resolved(characterRange)
    }

    func text(of range: CFRange, in control: AXControl) -> String? {
        guard let element = element(of: control),
              let value = parameterized(element, kAXStringForRangeParameterizedAttribute as String, range),
              CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    func bounds(of range: CFRange, in control: AXControl) -> CGRect? {
        guard let element = element(of: control),
              let value = parameterized(element, kAXBoundsForRangeParameterizedAttribute as String, range),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    func frame(of control: AXControl) -> CGRect? {
        guard let element = element(of: control),
              let position = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func title(of control: AXControl) -> String? {
        guard let element = element(of: control) else { return nil }
        return stringAttribute(element, kAXTitleAttribute as String)
    }

    func value(of control: AXControl) -> String? {
        guard let element = element(of: control) else { return nil }
        return stringAttribute(element, kAXValueAttribute as String)
    }

    func description(of control: AXControl) -> String? {
        guard let element = element(of: control) else { return nil }
        return stringAttribute(element, kAXDescriptionAttribute as String)
    }

    /// The retained child tokens are the caller's to release: the array can hold
    /// more than will be inspected (the reader caps how many it looks at), and
    /// dropping the tail without releasing it would leak one object per child.
    func children(of control: AXControl) -> [AXControl] {
        guard let element = element(of: control) else { return [] }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
        let array = raw as! CFArray
        var controls: [AXControl] = []
        controls.reserveCapacity(CFArrayGetCount(array))
        for index in 0..<CFArrayGetCount(array) {
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { continue }
            let child = Unmanaged<AXUIElement>.fromOpaque(pointer).takeUnretainedValue()
            AXUIElementSetMessagingTimeout(child, messagingTimeout)
            controls.append(AXControl(token: UInt(bitPattern: Unmanaged.passRetained(child).toOpaque())))
        }
        return controls
    }

    // MARK: - Token handling

    private func pointer(of control: AXControl) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: control.token)
    }

    private func element(of control: AXControl) -> AXUIElement? {
        guard let pointer = pointer(of: control) else { return nil }
        return Unmanaged<AXUIElement>.fromOpaque(pointer).takeUnretainedValue()
    }

    // MARK: - Attribute helpers

    /// A password field is refused. This is the same check the reader had before
    /// the seam existed; a role that cannot be read is not treated as protected
    /// here, and it has no readable text either way.
    private func isProtected(_ element: AXUIElement) -> Bool {
        Self.isProtected(role: stringAttribute(element, kAXRoleAttribute as String),
                         subrole: stringAttribute(element, kAXSubroleAttribute as String))
    }

    /// The protection rule as a pure function, so the rule itself can be pinned
    /// by a test without an Accessibility element to hand.
    static func isProtected(role: String?, subrole: String?) -> Bool {
        if subrole == "AXSecureTextField" { return true }
        if let role, role.hasSuffix("SecureTextField") { return true }
        return false
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    private func parameterized(_ element: AXUIElement, _ attribute: String, _ range: CFRange) -> CFTypeRef? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                                                         attribute as CFString,
                                                         parameter,
                                                         &value) == .success else { return nil }
        return value
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}

/// Runs every blocking Accessibility call on one dedicated serial queue and
/// returns value snapshots only. No Accessibility object leaves this type.
struct AccessibilityTextExtractor: TextExtracting {
    /// Thresholds are design initial values, not measured performance.
    struct Limits: Sendable {
        var messagingTimeout: Float = 0.3
        var maximumWordLength = 64
        var contextWindow = 64
        var maximumLabelLength = 120
        var labelRoles: Set<String>
        /// A short control is only asked for its direct children when it carries
        /// no label of its own: at most this many, never deeper.
        var maximumChildren = 8
        /// Only text children may answer for a control's label.
        var textChildRoles: Set<String>

        static let standard = Limits(labelRoles: [
            kAXButtonRole as String,
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            kAXPopUpButtonRole as String,
            kAXMenuItemRole as String,
            // 2026-09-19: Chrome exposes a navigation item like Google
            // Workspace's "Solutions" as a disclosure triangle, not a button,
            // which is why the same pointer position used to answer only
            // sometimes.
            kAXDisclosureTriangleRole as String,
        ], textChildRoles: [kAXStaticTextRole as String])
    }

    private let queue = DispatchQueue(label: "com.atat.HoverTranslate.accessibility", qos: .userInitiated)
    private let limits: Limits
    private let controls: AXControlReading
    /// Injectable so a test can place the pointer on a screen of its own size.
    private let primaryFrame: @Sendable () -> CGRect

    init(limits: Limits = .standard,
         controls: AXControlReading? = nil,
         primaryFrame: @escaping @Sendable () -> CGRect = { CGDisplayBounds(CGMainDisplayID()) }) {
        self.limits = limits
        self.controls = controls ?? SystemAXControls(messagingTimeout: limits.messagingTimeout)
        self.primaryFrame = primaryFrame
    }

    func extract(_ request: ExtractionRequest) async throws -> ExtractionSnapshot {
        let queue = self.queue
        let limits = self.limits
        let controls = self.controls
        // Resolved before the hop: the display frame is read once per request,
        // not once per query inside the read.
        let primaryFrame = self.primaryFrame()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try AccessibilityReader.read(request,
                                                 limits: limits,
                                                 controls: controls,
                                                 primaryFrame: primaryFrame)
                })
            }
        }
    }
}

/// All Accessibility reads. Deliberately free of app state so it can run on the
/// extractor serial queue, and free of Accessibility objects so the decisions it
/// makes are testable with a synthetic control.
private enum AccessibilityReader {
    /// Diagnoses why a hit failed; never logs extracted text.
    private static let log = Logger(subsystem: "com.atat.HoverTranslate", category: "accessibility")

    static func read(_ request: ExtractionRequest,
                     limits: AccessibilityTextExtractor.Limits,
                     controls: AXControlReading,
                     primaryFrame: CGRect) throws -> ExtractionSnapshot {
        guard controls.hasAccessibilityPermission() else { throw ExtractionFailure.permissionDenied }

        // One conversion for the whole read. Apple's hit interface and
        // AXRangeForPosition both take screen points whose origin is the top-left
        // of the primary display, while the pointer arrives in AppKit coordinates
        // (origin at the bottom-left of the same display). Converting once, here,
        // is what keeps "which control" and "which character" in the same place;
        // converting twice — or not at all — moves the hit somewhere else.
        let axPoint = CoordinateMapper.appKitToAX(request.point, primaryFrame: primaryFrame)

        // A selection the user already made wins over whatever word sits under
        // the pointer, and it is checked before the hit interface so a hit reads
        // no text through the word path at all. Only a hover request reaches
        // here: OCR has its own extractor and the manual entry point never enters
        // the read layer, so this needs no mode check.
        if let selection = selectionSnapshot(controls: controls,
                                            request: request,
                                            primaryFrame: primaryFrame,
                                            axPoint: axPoint) {
            return selection
        }

        guard let control = controls.control(at: axPoint) else {
            throw ExtractionFailure.positionUnresolved
        }
        defer { controls.release(control) }

        // The hit must belong to the application the user is pointing at, and
        // never to this tool.
        guard let owner = controls.owner(of: control), owner.pid > 0 else {
            log.debug("hit control has no pid for source pid=\(request.sourcePID, privacy: .public)")
            throw ExtractionFailure.unknownOwner
        }
        guard owner.pid == request.sourcePID, owner.pid != getpid() else {
            log.debug("hit pid=\(owner.pid, privacy: .public) is not source pid=\(request.sourcePID, privacy: .public)")
            throw ExtractionFailure.unknownOwner
        }

        if owner.isProtected { throw ExtractionFailure.blockedSensitive }

        let role = controls.role(of: control) ?? "-"
        let mapping = controls.range(at: axPoint, in: control)
        // One line per hit: the role and which category the position mapping
        // returned. Never the text, and never the coordinates.
        log.debug("hit role=\(role, privacy: .public) mapping=\(mapping.category, privacy: .public)")

        if case .resolved(let characterRange) = mapping {
            // v0.3 sentence mode. A short control has no sentence to find, so it
            // keeps the label path instead of gluing neighbouring menu items on.
            if request.mode == .sentence,
               !isShortLabel(role: role, limits: limits),
               let snapshot = sentence(control: control,
                                       controls: controls,
                                       characterRange: characterRange,
                                       primaryFrame: primaryFrame,
                                       request: request) {
                return snapshot
            }
            if let snapshot = exactWord(control: control,
                                        controls: controls,
                                        characterRange: characterRange,
                                        primaryFrame: primaryFrame,
                                        limits: limits,
                                        request: request) {
                return snapshot
            }
        }
        if let snapshot = boundedLabel(control: control,
                                       controls: controls,
                                       primaryFrame: primaryFrame,
                                       limits: limits,
                                       pid: owner.pid,
                                       request: request) {
            return snapshot
        }
        if case .unsupported = mapping {
            if let snapshot = browserLabel(control: control,
                                           controls: controls,
                                           primaryFrame: primaryFrame,
                                           limits: limits,
                                           request: request) {
                return snapshot
            }
            log.debug("control reports no position mapping for role=\(role, privacy: .public)")
            throw ExtractionFailure.notSupported
        }
        log.debug("no exact word or short label at point for role=\(role, privacy: .public)")
        throw ExtractionFailure.positionUnresolved
    }

    // MARK: - Hovered selection

    /// The selection the pointer is resting on, when the user already selected
    /// text and pointed at it.
    ///
    /// Order is deliberate: the focused control is asked for its selected range
    /// first, so the common negative case — nothing is selected — costs two
    /// calls and reads no text at all; the selection's own text is only read
    /// once the pointer is proven to be inside it. Every failure returns nil and
    /// lets the caller continue down the existing word/sentence/label path.
    /// Nothing here throws on purpose: a throw would be classified as a read
    /// failure and could reach the screenshot fallback.
    private static func selectionSnapshot(controls: AXControlReading,
                                         request: ExtractionRequest,
                                         primaryFrame: CGRect,
                                         axPoint: CGPoint) -> ExtractionSnapshot? {
        guard let focused = controls.focusedControl() else { return nil }
        defer { controls.release(focused) }
        let role = controls.role(of: focused) ?? "-"

        // The selection must belong to the application under the pointer; the
        // selection of a background application is not what the user pointed at.
        guard let owner = controls.owner(of: focused),
              owner.pid > 0,
              owner.pid == request.sourcePID else {
            log.debug("selection probe outcome=not-focus role=\(role, privacy: .public)")
            return nil
        }
        guard !owner.isProtected else {
            log.debug("selection probe outcome=protected role=\(role, privacy: .public)")
            return nil
        }
        guard let selectedRange = controls.selectedRange(of: focused), selectedRange.length > 0 else {
            log.debug("selection probe outcome=no-range role=\(role, privacy: .public)")
            return nil
        }
        guard let bounds = controls.bounds(of: selectedRange, in: focused),
              !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            log.debug("selection probe outcome=no-bounds role=\(role, privacy: .public)")
            return nil
        }

        // Without the index test the union rectangle of a multi-line selection
        // reports a hit for text that is not selected. An application that cannot
        // answer RangeForPosition leaves geometry as the only evidence there is.
        var pointerRange: CFRange?
        if case .resolved(let range) = controls.range(at: axPoint, in: focused) {
            pointerRange = range
        }
        guard SelectionHitPolicy.isHit(pointer: axPoint,
                                      selectionRect: bounds,
                                      pointerRange: pointerRange,
                                      selectedRange: selectedRange) else {
            log.debug("selection probe outcome=miss role=\(role, privacy: .public)")
            return nil
        }

        guard let text = controls.selectedText(of: focused) ?? controls.text(of: selectedRange, in: focused),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.debug("selection probe outcome=no-text role=\(role, privacy: .public)")
            return nil
        }
        // Over-long text is refused, never truncated: half a selection would
        // translate something the user did not choose.
        guard TextInputPolicy.isAllowed(text, limit: TextInputPolicy.defaultLimit) else {
            log.debug("selection probe outcome=too-long role=\(role, privacy: .public)")
            return nil
        }

        // An application that returns less text than the range it reported has
        // clipped the selection; the card has to say so rather than pass a
        // fragment off as the whole selection.
        let completeness: ExtractionCompleteness =
            (text as NSString).length < selectedRange.length ? .partial : .complete

        log.debug("selection probe outcome=hit role=\(role, privacy: .public)")
        return ExtractionSnapshot(text: text,
                                  context: nil,
                                  scope: .selection,
                                  completeness: completeness,
                                  source: .accessibility,
                                  sourcePID: request.sourcePID,
                                  sourceBundleID: request.sourceBundleID,
                                  wordFrame: CoordinateMapper.axRectToAppKit(bounds, primaryFrame: primaryFrame),
                                  generation: request.generation)
    }

    private static func isShortLabel(role: String, limits: AccessibilityTextExtractor.Limits) -> Bool {
        limits.labelRoles.contains(role)
    }

    // MARK: - Exact word

    private static func exactWord(control: AXControl,
                                  controls: AXControlReading,
                                  characterRange: CFRange,
                                  primaryFrame: CGRect,
                                  limits: AccessibilityTextExtractor.Limits,
                                  request: ExtractionRequest) -> ExtractionSnapshot? {
        // A whole paragraph reported for one position is not an exact word.
        guard characterRange.length <= limits.maximumWordLength else { return nil }

        let total = controls.characterCount(of: control)
        let windowStart = max(0, characterRange.location - limits.contextWindow)
        var windowEnd = characterRange.location + characterRange.length + limits.contextWindow
        if let total { windowEnd = min(windowEnd, total) }
        guard windowEnd > windowStart else { return nil }

        let window = CFRange(location: windowStart, length: windowEnd - windowStart)
        guard let text = controls.text(of: window, in: control) else { return nil }

        let offset = characterRange.location - windowStart
        guard let wordRange = TextResolver.wordRange(in: text, atUTF16Offset: offset) else { return nil }

        let wordLocation = windowStart + wordRange.location
        // The word must fully cover the range the application reported for the
        // pointer; otherwise this position was not resolved to a precise word.
        guard wordLocation <= characterRange.location,
              wordLocation + wordRange.length >= characterRange.location + characterRange.length else {
            return nil
        }

        let word = (text as NSString).substring(with: wordRange)
        var frame: CGRect?
        if let bounds = controls.bounds(of: CFRange(location: wordLocation, length: wordRange.length),
                                        in: control),
           bounds.width > 0, bounds.height > 0 {
            frame = CoordinateMapper.axRectToAppKit(bounds, primaryFrame: primaryFrame)
        }

        return ExtractionSnapshot(text: word,
                                  context: nil,
                                  scope: .word,
                                  completeness: .complete,
                                  source: .accessibility,
                                  sourcePID: request.sourcePID,
                                  sourceBundleID: request.sourceBundleID,
                                  wordFrame: frame,
                                  generation: request.generation)
    }

    // MARK: - Sentence

    /// The sentence around the hit, read from a bounded window.
    ///
    /// 2026-09-19: the window goes to the shared resolver, which folds the line
    /// breaks first (a wrapped sentence is one sentence) and then proves the
    /// boundaries. A window clipped at either end, or a fragment with no
    /// terminator, stays partial so the card can tell the user to select the
    /// full sentence instead of letting the model write the missing text.
    private static func sentence(control: AXControl,
                                 controls: AXControlReading,
                                 characterRange: CFRange,
                                 primaryFrame: CGRect,
                                 request: ExtractionRequest) -> ExtractionSnapshot? {
        let maximum = SentenceResolver.maximumWindowLength
        let total = controls.characterCount(of: control)
        let hit = characterRange.location
        var windowStart = max(0, hit - maximum / 2)
        var windowEnd = windowStart + maximum
        if let total, windowEnd > total {
            windowEnd = total
            windowStart = max(0, windowEnd - maximum)
        }
        guard windowEnd > windowStart else { return nil }

        let window = CFRange(location: windowStart, length: windowEnd - windowStart)
        guard let text = controls.text(of: window, in: control) else { return nil }
        guard let resolution = SentenceResolver.resolve(in: SentenceWindow(text: text,
                                                                          windowStart: windowStart,
                                                                          elementEnd: total),
                                                       atUTF16Offset: hit - windowStart) else { return nil }
        // Category only: which boundary was or was not proven, never the text.
        log.debug("sentence boundary=\(resolution.boundary.rawValue, privacy: .public)")

        var frame: CGRect?
        let range = resolution.originalRange
        if let bounds = controls.bounds(of: CFRange(location: windowStart + range.location, length: range.length),
                                        in: control),
           bounds.width > 0, bounds.height > 0 {
            frame = CoordinateMapper.axRectToAppKit(bounds, primaryFrame: primaryFrame)
        }

        return ExtractionSnapshot(text: resolution.text,
                                  context: nil,
                                  scope: .sentence,
                                  completeness: resolution.completeness,
                                  source: .accessibility,
                                  sourcePID: request.sourcePID,
                                  sourceBundleID: request.sourceBundleID,
                                  wordFrame: frame,
                                  generation: request.generation)
    }

    // MARK: - Short label

    /// Chrome often exposes a heading's leaf text or a navigation link without
    /// RangeForPosition. Read only the compact control actually hit, not a web
    /// area, text editor, ancestor, or document. This is a whole label, never a
    /// guessed word. A supported mapping that hit whitespace cannot use it.
    private static func browserLabel(control: AXControl,
                                     controls: AXControlReading,
                                     primaryFrame: CGRect,
                                     limits: AccessibilityTextExtractor.Limits,
                                     request: ExtractionRequest) -> ExtractionSnapshot? {
        guard let role = controls.role(of: control),
              role == "AXStaticText" || role == "AXLink",
              let rect = controls.frame(of: control),
              !rect.isNull, !rect.isInfinite,
              rect.width > 0, rect.width <= 1_200,
              rect.height > 0, rect.height <= 64,
              rect.contains(CoordinateMapper.appKitToAX(request.point, primaryFrame: primaryFrame)) else { return nil }
        if let count = controls.characterCount(of: control), count > limits.maximumLabelLength {
            return nil
        }
        let candidates = role == "AXStaticText"
            ? [controls.value(of: control), controls.title(of: control)]
            : [controls.title(of: control), controls.value(of: control)]
        guard let label = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }),
              label.count <= limits.maximumLabelLength,
              label.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return ExtractionSnapshot(text: label,
                                  context: nil,
                                  scope: .label,
                                  completeness: .complete,
                                  source: .accessibility,
                                  sourcePID: request.sourcePID,
                                  sourceBundleID: request.sourceBundleID,
                                  wordFrame: CoordinateMapper.axRectToAppKit(rect, primaryFrame: primaryFrame),
                                  generation: request.generation)
    }

    /// Only short controls may fall back to a whole label, and the result is
    /// reported as a label scope, never as an exact word.
    ///
    /// 2026-09-19: a trusted short control has to prove it is the control under
    /// the pointer (a usable rect that contains the point), and its label is read
    /// in the order the design names — title, value, description, then its one
    /// direct text child. Nothing is guessed from an ambiguous control: the
    /// existing word/sentence and OCR paths stay in charge.
    private static func boundedLabel(control: AXControl,
                                     controls: AXControlReading,
                                     primaryFrame: CGRect,
                                     limits: AccessibilityTextExtractor.Limits,
                                     pid: pid_t,
                                     request: ExtractionRequest) -> ExtractionSnapshot? {
        guard let role = controls.role(of: control),
              limits.labelRoles.contains(role) else { return nil }
        let axPoint = CoordinateMapper.appKitToAX(request.point, primaryFrame: primaryFrame)
        guard let rect = controls.frame(of: control),
              isUsable(rect),
              rect.contains(axPoint) else {
            log.debug("short control role=\(role, privacy: .public) origin=out-of-bounds")
            return nil
        }

        let readers: [(String, () -> String?)] = [
            ("title", { controls.title(of: control) }),
            ("value", { controls.value(of: control) }),
            ("description", { controls.description(of: control) }),
        ]
        var label: String?
        var origin = "none"
        for (name, read) in readers where label == nil {
            if let candidate = shortLabel(read(), limit: limits.maximumLabelLength) {
                label = candidate
                origin = name
            }
        }
        if label == nil,
           let child = textChildLabel(of: control,
                                      ownedBy: pid,
                                      in: rect,
                                      controls: controls,
                                      limits: limits) {
            label = child
            origin = "child"
        }
        guard let label else {
            log.debug("short control role=\(role, privacy: .public) origin=none")
            return nil
        }
        // Category only: which attribute answered, never the label itself.
        log.debug("short control role=\(role, privacy: .public) origin=\(origin, privacy: .public)")

        return ExtractionSnapshot(text: label,
                                  context: nil,
                                  scope: .label,
                                  completeness: .complete,
                                  source: .accessibility,
                                  sourcePID: request.sourcePID,
                                  sourceBundleID: request.sourceBundleID,
                                  wordFrame: CoordinateMapper.axRectToAppKit(rect, primaryFrame: primaryFrame),
                                  generation: request.generation)
    }

    /// The one direct text child of a trusted short control, or nil.
    ///
    /// Only the direct children are looked at, at most `maximumChildren` of
    /// them, and the whole subtree below them is never walked. Each child has to
    /// belong to the same application, overlap the control's own rect and carry
    /// a text role. Two non-empty candidates are not concatenated: an ambiguous
    /// control has no label, which leaves the existing fallbacks as the only
    /// next steps.
    private static func textChildLabel(of control: AXControl,
                                       ownedBy pid: pid_t,
                                       in parentRect: CGRect,
                                       controls: AXControlReading,
                                       limits: AccessibilityTextExtractor.Limits) -> String? {
        let children = controls.children(of: control)
        // Every token handed out is released, including the tail that is never
        // inspected.
        defer { children.forEach { controls.release($0) } }

        var labels: [String] = []
        for child in children.prefix(limits.maximumChildren) {
            guard let owner = controls.owner(of: child),
                  owner.pid == pid,
                  !owner.isProtected,
                  let role = controls.role(of: child),
                  limits.textChildRoles.contains(role),
                  let rect = controls.frame(of: child),
                  rect.intersects(parentRect),
                  let label = shortLabel(controls.value(of: child) ?? controls.title(of: child),
                                         limit: limits.maximumLabelLength) else { continue }
            labels.append(label)
        }
        return labels.count == 1 ? labels[0] : nil
    }

    /// A label candidate: non-empty, single line, inside the design's limit.
    /// Anything longer is help text or a document, never a control's label.
    private static func shortLabel(_ candidate: String?, limit: Int) -> String? {
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              trimmed.count <= limit else { return nil }
        return trimmed
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
    }
}
