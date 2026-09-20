import CoreGraphics
import XCTest
@testable import HoverTranslate

/// The hit path, driven by a synthetic control instead of a running application.
///
/// The regression this file exists for: the reader used to hand the AppKit
/// pointer to AXUIElementCopyElementAtPosition and only convert it for the
/// character lookup, so "which control" and "which character" were resolved at
/// two different places on screen.
final class AccessibilityTextExtractorTests: XCTestCase {
    /// A 900-point-tall primary display, so the two origins differ by exactly
    /// 900 points and a missing conversion cannot be overlooked.
    private let primary = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    private func request(point: CGPoint, mode: QueryMode = .word) -> ExtractionRequest {
        ExtractionRequest(point: point,
                          sourcePID: 4_242,
                          sourceBundleID: "com.example.reader",
                          generation: 7,
                          mode: mode)
    }

    /// The frame is captured as a value: the extractor takes a sendable closure.
    private func extractor(_ controls: FakeAXControls) -> AccessibilityTextExtractor {
        let frame = primary
        return AccessibilityTextExtractor(controls: controls, primaryFrame: { frame })
    }

    /// A control that answers like a text area holding a document.
    private func scriptedControl(_ controls: FakeAXControls,
                                 document: String,
                                 mapping: AXPositionMapping) {
        controls.document = document
        controls.owner = AXControlOwner(pid: 4_242, isProtected: false)
        controls.role = "AXTextArea"
        controls.mapping = mapping
        controls.bounds = CGRect(x: 100, y: 100, width: 40, height: 16)
    }

    // MARK: - R1: one conversion, used by both position calls

    func testTheHitIsAskedForTheAXPointAndNotTheAppKitPoint() async throws {
        let controls = FakeAXControls()
        controls.returnsControl = false

        _ = try? await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(controls.hitPoints, [CGPoint(x: 100, y: 100)],
                       "the hit interface takes a top-left origin; (100, 800) in AppKit is (100, 100) here")
    }

    func testTheCharacterLookupUsesTheSameConvertedPoint() async throws {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "Open Settings here",
                        mapping: .resolved(CFRange(location: 0, length: 4)))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(controls.hitPoints, [CGPoint(x: 100, y: 100)])
        XCTAssertEqual(controls.rangePoints, [CGPoint(x: 100, y: 100)],
                       "the same point resolves the control and the character, never two different ones")
        XCTAssertEqual(controls.hitPoints.count, 1, "the hit is asked once per read")
        XCTAssertEqual(snapshot.text, "Open")
        XCTAssertEqual(snapshot.scope, .word)
        // 100 + 16 = 116 from the top of a 900-point screen is 784 from the bottom.
        XCTAssertEqual(snapshot.wordFrame, CGRect(x: 100, y: 784, width: 40, height: 16),
                       "the reported frame comes back in AppKit coordinates")
    }

    func testTheConversionCoversTopMiddleAndBottomOfThePrimaryScreen() async throws {
        for (appKitY, axY) in [(2, 898), (450, 450), (898, 2)] {
            let controls = FakeAXControls()
            controls.returnsControl = false
            _ = try? await extractor(controls).extract(request(point: CGPoint(x: 300, y: CGFloat(appKitY))))
            XCTAssertEqual(controls.hitPoints, [CGPoint(x: 300, y: CGFloat(axY))],
                           "AppKit y=\(appKitY) is AX y=\(axY) on a 900-point screen")
        }
    }

    func testPointsOnASecondaryScreenAboveOrLeftOfThePrimaryKeepTheirOffset() async throws {
        let above = FakeAXControls()
        above.returnsControl = false
        _ = try? await extractor(above).extract(request(point: CGPoint(x: 100, y: 1_000)))
        XCTAssertEqual(above.hitPoints, [CGPoint(x: 100, y: -100)],
                       "a screen above the primary maps to negative AX y")

        let left = FakeAXControls()
        left.returnsControl = false
        _ = try? await extractor(left).extract(request(point: CGPoint(x: -300, y: 400)))
        XCTAssertEqual(left.hitPoints, [CGPoint(x: -300, y: 500)],
                       "a screen to the left keeps its negative x")
    }

    // MARK: - Policy refusals happen before any text is read

    func testASourceMismatchIsRefusedBeforeAnyTextIsRead() async {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "Open Settings", mapping: .resolved(CFRange(location: 0, length: 4)))
        controls.owner = AXControlOwner(pid: 9_999, isProtected: false)

        await assertFailure(.unknownOwner, from: controls)
        XCTAssertEqual(controls.textReads, 0)
        XCTAssertEqual(controls.releases, 1, "the control is released even on a refusal")
    }

    func testAProtectedControlIsRefusedBeforeAnyTextIsRead() async {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "hunter2", mapping: .resolved(CFRange(location: 0, length: 7)))
        controls.owner = AXControlOwner(pid: 4_242, isProtected: true)

        await assertFailure(.blockedSensitive, from: controls)
        XCTAssertEqual(controls.textReads, 0)
    }

    func testWithoutAccessibilityPermissionNothingIsAskedOfTheSystem() async {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "Open Settings", mapping: .resolved(CFRange(location: 0, length: 4)))
        controls.permission = false

        await assertFailure(.permissionDenied, from: controls)
        XCTAssertTrue(controls.hitPoints.isEmpty)
        XCTAssertEqual(controls.textReads, 0)
    }

    // MARK: - Position mapping categories still decide the failure

    func testAControlWithNoPositionMappingIsNotSupportedSoOCRMayStillBeConsidered() async {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "Open Settings", mapping: .unsupported)

        await assertFailure(.notSupported, from: controls)
    }

    func testAnAcceptedCallWithoutAResolvedRangeIsNotAPositionFailure() async {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "Open Settings", mapping: .none)

        await assertFailure(.positionUnresolved, from: controls)
    }

    func testAWhitespacePositionIsNotResolvedToANearbyWord() async {
        let controls = FakeAXControls()
        // The application reports the character after the word, which the word
        // range does not cover: this position is not a precise word.
        scriptedControl(controls, document: "Open Settings", mapping: .resolved(CFRange(location: 4, length: 1)))

        await assertFailure(.positionUnresolved, from: controls)
    }

    // MARK: - The label path still works through the seam

    func testAShortControlStillAnswersWithItsWholeLabel() async throws {
        let controls = FakeAXControls()
        controls.owner = AXControlOwner(pid: 4_242, isProtected: false)
        controls.role = "AXButton"
        controls.title = "Open Settings"
        controls.mapping = .unsupported
        // AX (20, 780) is where the AppKit pointer below lands, so the control
        // is under it; a label is only read for a control the pointer is on.
        controls.frame = CGRect(x: 20, y: 780, width: 120, height: 24)

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 40, y: 100)))

        XCTAssertEqual(snapshot.text, "Open Settings")
        XCTAssertEqual(snapshot.scope, .label)
        XCTAssertEqual(snapshot.wordFrame, CGRect(x: 20, y: 96, width: 120, height: 24),
                       "the control rect is converted back to AppKit coordinates")
    }

    // MARK: - Trusted short controls (2026-09-19 web hit design)

    /// The Google Workspace navigation case: the item is a disclosure triangle
    /// whose own title and value are empty and whose only direct child holds
    /// the visible text.
    private func scriptDisclosureTriangle(_ controls: FakeAXControls, label: String) {
        controls.role = "AXDisclosureTriangle"
        controls.mapping = .unsupported
        controls.frame = CGRect(x: 80, y: 80, width: 120, height: 30)
        controls.childrenTokens = [11]
        controls.childRoles[11] = "AXStaticText"
        controls.childValues[11] = label
        controls.childFrames[11] = CGRect(x: 84, y: 84, width: 100, height: 20)
        controls.childOwners[11] = AXControlOwner(pid: 4_242, isProtected: false)
    }

    func testADisclosureTriangleAnswersWithItsOnlyTextChild() async throws {
        let controls = FakeAXControls()
        scriptDisclosureTriangle(controls, label: "Solutions")

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.text, "Solutions")
        XCTAssertEqual(snapshot.scope, .label, "a whole control label is never an exact word")
    }

    /// The same control answers the same label wherever the pointer sits inside
    /// it: on the text strokes and on the control's own padding.
    func testTheTextAndThePaddingOfOneControlGiveTheSameLabel() async throws {
        let onText = FakeAXControls()
        scriptDisclosureTriangle(onText, label: "Solutions")
        // AX (100, 100): inside the control and inside its text child.
        let fromText = try await extractor(onText).extract(request(point: CGPoint(x: 100, y: 800)))

        let onPadding = FakeAXControls()
        scriptDisclosureTriangle(onPadding, label: "Solutions")
        // AX (190, 108): inside the control, to the right of the text child.
        let fromPadding = try await extractor(onPadding).extract(request(point: CGPoint(x: 190, y: 792)))

        XCTAssertEqual(fromText.text, "Solutions")
        XCTAssertEqual(fromPadding.text, "Solutions")
        XCTAssertEqual(fromPadding.scope, .label)
    }

    /// A pointer on the text child itself resolves through the existing bounded
    /// browser path, and has to agree with the control's own label.
    func testTheHitControlAndItsTextChildGiveTheSameLabel() async throws {
        let controls = FakeAXControls()
        controls.role = "AXStaticText"
        controls.mapping = .unsupported
        controls.value = "Solutions"
        controls.frame = CGRect(x: 84, y: 84, width: 100, height: 20)

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.text, "Solutions")
        XCTAssertEqual(snapshot.scope, .label)
    }

    func testALabelIsReadInTheDocumentedOrder() async throws {
        let cases: [(String?, String?, String?, String)] = [
            ("Stored", "Value", "Help", "Stored"),
            (nil, "Value", "Help", "Value"),
            (nil, nil, "Help", "Help"),
        ]
        for (title, value, description, expected) in cases {
            let controls = FakeAXControls()
            controls.role = "AXButton"
            controls.mapping = .unsupported
            controls.frame = CGRect(x: 80, y: 80, width: 120, height: 30)
            controls.title = title
            controls.value = value
            controls.controlDescription = description

            let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

            XCTAssertEqual(snapshot.text, expected)
            XCTAssertEqual(snapshot.scope, .label)
        }
    }

    /// An ambiguous control has no label, and the reader never guesses: two text
    /// children, an over-long one, a multi-line one, one that does not overlap
    /// the control, one owned by another process or one that is not text.
    func testAmbiguousOrUnusableChildrenAreRefused() async {
        let cases: [(String, (FakeAXControls) -> Void)] = [
            ("two text children", {
                $0.childrenTokens = [11, 12]
                $0.childRoles[12] = "AXStaticText"
                $0.childValues[12] = "Products"
                $0.childFrames[12] = CGRect(x: 84, y: 84, width: 100, height: 20)
                $0.childOwners[12] = AXControlOwner(pid: 4_242, isProtected: false)
            }),
            ("a child longer than the label limit", {
                $0.childValues[11] = String(repeating: "x", count: 121)
            }),
            ("a multi-line child", { $0.childValues[11] = "First\nSecond" }),
            ("a child that does not overlap the control", {
                $0.childFrames[11] = CGRect(x: 900, y: 900, width: 40, height: 20)
            }),
            ("a child owned by another process", {
                $0.childOwners[11] = AXControlOwner(pid: 9_999, isProtected: false)
            }),
            ("a child that carries no text role", { $0.childRoles[11] = "AXImage" }),
        ]
        for (name, adjust) in cases {
            let controls = FakeAXControls()
            scriptDisclosureTriangle(controls, label: "Solutions")
            adjust(controls)
            await assertFailure(.notSupported, from: controls)
            XCTAssertEqual(controls.textReads, 0, "\(name): no document range is read")
        }
    }

    func testAProtectedChildIsNeverRead() async {
        let controls = FakeAXControls()
        scriptDisclosureTriangle(controls, label: "hunter2")
        controls.childOwners[11] = AXControlOwner(pid: 4_242, isProtected: true)

        await assertFailure(.notSupported, from: controls)
        XCTAssertNil(controls.valueReads[11], "a protected child's text is never read")
    }

    func testAShortControlHasToBeUnderThePointer() async {
        let controls = FakeAXControls()
        controls.role = "AXButton"
        controls.title = "Open Settings"
        controls.mapping = .unsupported
        controls.frame = CGRect(x: 500, y: 500, width: 120, height: 24)

        await assertFailure(.notSupported, from: controls)
        XCTAssertNil(controls.valueReads[FakeAXControls.hitToken],
                     "a control the pointer is not on is never asked for a label")
    }

    func testAtMostEightChildrenAreInspected() async {
        let controls = FakeAXControls()
        controls.role = "AXDisclosureTriangle"
        controls.mapping = .unsupported
        controls.frame = CGRect(x: 80, y: 80, width: 120, height: 30)
        let tokens: [UInt] = Array(UInt(11)...UInt(20))
        controls.childrenTokens = tokens
        for token in tokens {
            controls.childRoles[token] = "AXStaticText"
            controls.childValues[token] = "Item \(token)"
            controls.childFrames[token] = CGRect(x: 84, y: 84, width: 100, height: 20)
            controls.childOwners[token] = AXControlOwner(pid: 4_242, isProtected: false)
        }

        await assertFailure(.notSupported, from: controls)
        XCTAssertNil(controls.valueReads[19], "the ninth child is never asked for its text")
        XCTAssertNil(controls.valueReads[20], "the tenth child is never asked for its text")
        XCTAssertEqual(controls.releases, 11, "every child token handed out is released, plus the hit control")
    }

    // MARK: - Sentence mode over the same seam

    private func sentenceOffset(of needle: String, in document: String) -> CFRange {
        CFRange(location: (document as NSString).range(of: needle).location, length: (needle as NSString).length)
    }

    func testASentenceWrappedOverTwoLinesIsReadWhole() async throws {
        let controls = FakeAXControls()
        let document = "First one is here. This sentence wraps\nonto another line. Third one is here."
        scriptedControl(controls, document: document, mapping: .resolved(sentenceOffset(of: "wraps", in: document)))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800), mode: .sentence))

        XCTAssertEqual(snapshot.text, "This sentence wraps onto another line.",
                       "a single line break is typography, not a sentence end")
        XCTAssertEqual(snapshot.scope, .sentence)
        XCTAssertEqual(snapshot.completeness, .complete)
    }

    func testASentenceClippedByTheReadWindowIsPartial() async throws {
        let controls = FakeAXControls()
        let document = String(repeating: "x", count: 3_000) + " change the language here."
        scriptedControl(controls,
                        document: document,
                        mapping: .resolved(sentenceOffset(of: "language", in: document)))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800), mode: .sentence))

        XCTAssertEqual(snapshot.scope, .sentence)
        XCTAssertEqual(snapshot.completeness, .partial, "a clipped window can never prove the whole sentence")
    }

    // MARK: - Browser text without position mapping

    func testShortBrowserTextAndLinksHaveABoundedLabelFallback() async throws {
        for role in ["AXStaticText", "AXLink"] {
            let controls = FakeAXControls()
            controls.role = role
            controls.mapping = .unsupported
            controls.value = "按住 Option 悬停翻译"
            controls.frame = CGRect(x: 80, y: 80, width: 300, height: 30)
            let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))
            XCTAssertEqual(snapshot.text, "按住 Option 悬停翻译")
            XCTAssertEqual(snapshot.scope, .label, "a whole label is never an exact word")
        }
    }

    func testBrowserLabelDoesNotReadAnUnboundedDocument() async {
        let controls = FakeAXControls()
        controls.role = "AXStaticText"
        controls.mapping = .unsupported
        controls.document = String(repeating: "x", count: 500)
        controls.value = controls.document
        controls.frame = CGRect(x: 80, y: 80, width: 400, height: 30)
        await assertFailure(.notSupported, from: controls)
        XCTAssertEqual(controls.labelReads, 0, "reject a known large document before asking for its value")
    }

    func testBrowserLabelRequiresAPointedCompactSingleLine() async {
        for (frame, text) in [
            (CGRect(x: 200, y: 200, width: 100, height: 20), "Settings"),
            (CGRect(x: 80, y: 80, width: 400, height: 400), "Settings"),
            (CGRect(x: 80, y: 80, width: 300, height: 30), "First\nSecond"),
            (CGRect(x: 80, y: 80, width: 300, height: 30), String(repeating: "x", count: 121))
        ] {
            let controls = FakeAXControls()
            controls.role = "AXLink"
            controls.mapping = .unsupported
            controls.value = text
            controls.frame = frame
            await assertFailure(.notSupported, from: controls)
        }
    }

    func testBrowserLabelNeverReadsProtectedText() async {
        let controls = FakeAXControls()
        controls.role = "AXStaticText"
        controls.owner = AXControlOwner(pid: 4_242, isProtected: true)
        controls.value = "private"
        controls.frame = CGRect(x: 80, y: 80, width: 300, height: 30)
        await assertFailure(.blockedSensitive, from: controls)
        XCTAssertEqual(controls.labelReads, 0)
    }

    // MARK: - The protection rule itself

    func testTheProtectionRuleCoversTheSecureRoleAndSubrole() {
        XCTAssertTrue(SystemAXControls.isProtected(role: "AXSecureTextField", subrole: nil))
        XCTAssertTrue(SystemAXControls.isProtected(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertTrue(SystemAXControls.isProtected(role: "AXSecureTextField", subrole: "AXSecureTextField"))
        XCTAssertFalse(SystemAXControls.isProtected(role: "AXTextArea", subrole: nil))
        XCTAssertFalse(SystemAXControls.isProtected(role: "AXStaticText", subrole: nil))
        XCTAssertFalse(SystemAXControls.isProtected(role: nil, subrole: nil))
    }

    // MARK: - A selection that is already on screen

    /// A focused text area holding a selection, scripted without an application.
    private func scriptedSelection(_ controls: FakeAXControls,
                                   text: String,
                                   range: CFRange,
                                   bounds: CGRect,
                                   mapping: AXPositionMapping = .resolved(CFRange(location: 20, length: 5))) {
        controls.document = text
        controls.owner = AXControlOwner(pid: 4_242, isProtected: false)
        controls.role = "AXTextArea"
        controls.mapping = mapping
        controls.bounds = bounds
        controls.focused = AXControl(token: 2)
        controls.selectedRange = range
        controls.selectedText = text
    }

    func testAHoveredSelectionBecomesOneSelectionSnapshot() async throws {
        let controls = FakeAXControls()
        let sentence = "Charge the battery before the trip."
        scriptedSelection(controls,
                          text: sentence,
                          range: CFRange(location: 10, length: (sentence as NSString).length),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.text, sentence)
        XCTAssertEqual(snapshot.scope, .selection)
        XCTAssertEqual(snapshot.completeness, .complete)
        XCTAssertEqual(snapshot.mode, .selection, "the request mode follows the scope instead of a second guess")
        XCTAssertEqual(snapshot.wordFrame, CGRect(x: 100, y: 784, width: 200, height: 16),
                       "the selection rect comes back in AppKit coordinates")
        XCTAssertTrue(controls.hitPoints.isEmpty, "a selection hit never asks the hit interface")
        XCTAssertEqual(controls.focusedReads, 1)
    }

    func testASelectionIsReadThroughARangeWhenTheAppHasNoSelectedTextAttribute() async throws {
        let controls = FakeAXControls()
        let sentence = "Charge the battery before the trip."
        scriptedSelection(controls,
                          text: sentence,
                          range: CFRange(location: 0, length: (sentence as NSString).length),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))
        controls.selectedText = nil

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.text, sentence)
        XCTAssertEqual(controls.textReads, 1, "the range read is the fallback for the selection text")
    }

    func testAClippedSelectionIsReportedAsPartial() async throws {
        let controls = FakeAXControls()
        scriptedSelection(controls,
                          text: "Charge the battery",
                          range: CFRange(location: 10, length: 40),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.completeness, .partial,
                       "fewer characters than the range the app reported means the app clipped it")
    }

    func testGeometryAloneDecidesWhenTheAppCannotReportARangeForThePointer() async throws {
        let controls = FakeAXControls()
        let sentence = "Charge the battery before the trip."
        scriptedSelection(controls,
                          text: sentence,
                          range: CFRange(location: 10, length: (sentence as NSString).length),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16),
                          mapping: .unsupported)

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.scope, .selection, "an app without RangeForPosition still gets the gesture")
    }

    func testTheIndexTestRejectsAPointerInTheUnionRectOfAMultiLineSelection() async throws {
        let controls = FakeAXControls()
        scriptedSelection(controls,
                          text: "Charge the battery before the trip.",
                          range: CFRange(location: 10, length: 35),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16),
                          mapping: .resolved(CFRange(location: 60, length: 5)))
        controls.document = "Open Settings"
        controls.mapping = .resolved(CFRange(location: 0, length: 4))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.scope, .word,
                       "geometry alone would hit; the index says the pointer is outside the selection")
    }

    func testAPointerOutsideTheSelectionStillTranslatesTheWordUnderIt() async throws {
        let controls = FakeAXControls()
        scriptedSelection(controls,
                          text: "Charge the battery before the trip.",
                          range: CFRange(location: 10, length: 35),
                          bounds: CGRect(x: 300, y: 300, width: 200, height: 16))
        controls.document = "Open Settings"
        controls.mapping = .resolved(CFRange(location: 0, length: 4))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.text, "Open")
        XCTAssertEqual(snapshot.scope, .word)
    }

    func testASelectionWinsEvenWhenTheSentenceModifierIsHeld() async throws {
        let controls = FakeAXControls()
        let sentence = "Charge the battery before the trip."
        scriptedSelection(controls,
                          text: sentence,
                          range: CFRange(location: 10, length: (sentence as NSString).length),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800),
                                                                     mode: .sentence))

        XCTAssertEqual(snapshot.scope, .selection,
                       "a hovered selection wins over Control instead of turning into a sentence")
    }

    func testWithoutASelectionTheHoverPathIsUnchanged() async throws {
        let controls = FakeAXControls()
        scriptedControl(controls, document: "Open Settings", mapping: .resolved(CFRange(location: 0, length: 4)))
        controls.focused = AXControl(token: 2)
        controls.selectedRange = CFRange(location: 4, length: 0)

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.scope, .word)
        XCTAssertEqual(controls.selectionTextReads, 0, "no selection means no selection text is read")
    }

    func testASelectionInAnotherApplicationIsNotRead() async throws {
        let controls = FakeAXControls()
        scriptedSelection(controls,
                          text: "Charge the battery before the trip.",
                          range: CFRange(location: 10, length: 35),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))
        controls.focusedOwner = AXControlOwner(pid: 9_999, isProtected: false)
        controls.document = "Open Settings"
        controls.mapping = .resolved(CFRange(location: 0, length: 4))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.scope, .word)
        XCTAssertEqual(controls.selectionTextReads, 0, "the selection of a background application is never read")
    }

    func testAProtectedFocusedControlIsNeverRead() async throws {
        let controls = FakeAXControls()
        scriptedSelection(controls,
                          text: "hunter2 hunter2 hunter2",
                          range: CFRange(location: 0, length: 22),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))
        controls.focusedOwner = AXControlOwner(pid: 4_242, isProtected: true)
        controls.document = "Open Settings"
        controls.mapping = .resolved(CFRange(location: 0, length: 4))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.scope, .word, "the refusal falls back instead of failing the read")
        XCTAssertEqual(controls.selectionTextReads, 0)
    }

    func testAnOverLongSelectionIsRefusedInsteadOfTruncated() async throws {
        let controls = FakeAXControls()
        let huge = String(repeating: "x", count: 4_001)
        scriptedSelection(controls,
                          text: huge,
                          range: CFRange(location: 0, length: 4_001),
                          bounds: CGRect(x: 100, y: 100, width: 200, height: 16))
        controls.document = "Open Settings"
        controls.mapping = .resolved(CFRange(location: 0, length: 4))

        let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))

        XCTAssertEqual(snapshot.text, "Open", "an over-long selection is refused, never cut in half")
        XCTAssertEqual(snapshot.scope, .word)
    }

    // MARK: - Helpers

    private func assertFailure(_ expected: ExtractionFailure,
                               from controls: FakeAXControls,
                               file: StaticString = #filePath,
                               line: UInt = #line) async {
        do {
            let snapshot = try await extractor(controls).extract(request(point: CGPoint(x: 100, y: 800)))
            XCTFail("expected \(expected), got \(snapshot.text)", file: file, line: line)
        } catch let failure as ExtractionFailure {
            XCTAssertEqual(failure, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }
}

/// A synthetic control: scriptable answers, and a record of every position the
/// reader asked about.
///
/// The recorder is lock-guarded. The unchecked conformance covers the hop onto
/// the extractor's serial queue — mutations happen on that queue and reads happen
/// on the test thread after the result was awaited — not an ignored race.
final class FakeAXControls: AXControlReading, @unchecked Sendable {
    /// The token the scripted hit control answers to. Direct children use any
    /// other token, so one fake can carry both.
    static let hitToken: UInt = 1

    // Scripted before the read starts and never mutated during it.
    var returnsControl = true
    var permission = true
    var owner: AXControlOwner? = AXControlOwner(pid: 4_242, isProtected: false)
    var role: String? = "AXTextArea"
    var document = ""
    var mapping: AXPositionMapping = .none
    var bounds: CGRect?
    var frame: CGRect?
    var title: String?
    var value: String?
    var controlDescription: String?
    /// Direct children of the hit control, by token. Nothing deeper is scripted:
    /// the reader is not allowed to walk the tree.
    var childrenTokens: [UInt] = []
    var childRoles: [UInt: String] = [:]
    var childValues: [UInt: String] = [:]
    var childTitles: [UInt: String] = [:]
    var childFrames: [UInt: CGRect] = [:]
    var childOwners: [UInt: AXControlOwner] = [:]
    /// The focused element is a different element from the one under the
    /// pointer, so it carries its own scripted owner and selection.
    var focusedToken: UInt = 2
    var focusedOwner: AXControlOwner? = AXControlOwner(pid: 4_242, isProtected: false)
    var focused: AXControl?
    var selectedRange: CFRange?
    var selectedText: String?

    private let lock = NSLock()
    private var recordedHitPoints: [CGPoint] = []
    private var recordedRangePoints: [CGPoint] = []
    private var recordedTextReads = 0
    private var recordedReleases = 0
    private var recordedLabelReads = 0
    private var recordedFocusedReads = 0
    private var recordedSelectionTextReads = 0
    private var recordedValueReads: [UInt: Int] = [:]

    var hitPoints: [CGPoint] { locked { recordedHitPoints } }
    var rangePoints: [CGPoint] { locked { recordedRangePoints } }
    var textReads: Int { locked { recordedTextReads } }
    var releases: Int { locked { recordedReleases } }
    var labelReads: Int { locked { recordedLabelReads } }
    var focusedReads: Int { locked { recordedFocusedReads } }
    var selectionTextReads: Int { locked { recordedSelectionTextReads } }
    /// How often one control's text attribute was asked for, by token.
    var valueReads: [UInt: Int] { locked { recordedValueReads } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func hasAccessibilityPermission() -> Bool { permission }

    func control(at point: CGPoint) -> AXControl? {
        locked { recordedHitPoints.append(point) }
        return returnsControl ? AXControl(token: 1) : nil
    }

    func release(_ control: AXControl) { locked { recordedReleases += 1 } }

    func owner(of control: AXControl) -> AXControlOwner? {
        if control.token == focusedToken { return focusedOwner }
        return control.token == Self.hitToken ? owner : childOwners[control.token]
    }

    func focusedControl() -> AXControl? {
        locked { recordedFocusedReads += 1 }
        return focused
    }

    func selectedRange(of control: AXControl) -> CFRange? { selectedRange }

    func selectedText(of control: AXControl) -> String? {
        locked { recordedSelectionTextReads += 1 }
        return selectedText
    }

    func role(of control: AXControl) -> String? {
        control.token == Self.hitToken ? role : childRoles[control.token]
    }

    func characterCount(of control: AXControl) -> Int? {
        document.isEmpty ? nil : (document as NSString).length
    }

    func range(at point: CGPoint, in control: AXControl) -> AXPositionMapping {
        locked { recordedRangePoints.append(point) }
        return mapping
    }

    func text(of range: CFRange, in control: AXControl) -> String? {
        locked { recordedTextReads += 1 }
        let text = document as NSString
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= text.length else { return nil }
        return text.substring(with: NSRange(location: range.location, length: range.length))
    }

    func bounds(of range: CFRange, in control: AXControl) -> CGRect? { bounds }

    func frame(of control: AXControl) -> CGRect? {
        control.token == Self.hitToken ? frame : childFrames[control.token]
    }

    func title(of control: AXControl) -> String? {
        locked { recordedLabelReads += 1 }
        return control.token == Self.hitToken ? title : childTitles[control.token]
    }

    func value(of control: AXControl) -> String? {
        locked {
            recordedLabelReads += 1
            recordedValueReads[control.token, default: 0] += 1
        }
        return control.token == Self.hitToken ? value : childValues[control.token]
    }

    func description(of control: AXControl) -> String? {
        control.token == Self.hitToken ? controlDescription : nil
    }

    func children(of control: AXControl) -> [AXControl] {
        guard control.token == Self.hitToken else { return [] }
        return childrenTokens.map { AXControl(token: $0) }
    }
}
