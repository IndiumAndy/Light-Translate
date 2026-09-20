import XCTest
@testable import HoverTranslate

final class CoordinateMapperTests: XCTestCase {
    func testMainDisplayReferenceAlsoWorksForDisplayAbove() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(CoordinateMapper.appKitToAX(
            CGPoint(x: 100, y: 800), primaryFrame: primary),
            CGPoint(x: 100, y: 100))
        XCTAssertEqual(CoordinateMapper.appKitToAX(
            CGPoint(x: -100, y: 1000), primaryFrame: primary),
            CGPoint(x: -100, y: -100))
    }

    func testRectRoundTripFlipsUsingHeight() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let axRect = CGRect(x: 100, y: 100, width: 50, height: 20)
        let appKitRect = CoordinateMapper.axRectToAppKit(axRect, primaryFrame: primary)
        XCTAssertEqual(appKitRect, CGRect(x: 100, y: 780, width: 50, height: 20))
    }

    func testCardIsPlacedBelowTheHitWord() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hit = CGRect(x: 100, y: 700, width: 40, height: 16)
        let card = CoordinateMapper.cardRect(size: CGSize(width: 320, height: 80),
                                             hit: hit, visible: visible)
        XCTAssertEqual(card, CGRect(x: 100, y: 612, width: 320, height: 80))
        XCTAssertFalse(card.intersects(hit))
    }

    func testCardFlipsAboveWhenThereIsNoRoomBelow() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hit = CGRect(x: 100, y: 30, width: 40, height: 16)
        let card = CoordinateMapper.cardRect(size: CGSize(width: 320, height: 80),
                                             hit: hit, visible: visible)
        // hit.maxY (46) + gap (8) = 54, still clear of the hit rect.
        XCTAssertEqual(card, CGRect(x: 100, y: 54, width: 320, height: 80))
        XCTAssertFalse(card.intersects(hit))
    }

    func testCardIsClampedIntoTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hit = CGRect(x: 1400, y: 700, width: 40, height: 16)
        let card = CoordinateMapper.cardRect(size: CGSize(width: 320, height: 80),
                                             hit: hit, visible: visible)
        XCTAssertEqual(card.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(card.maxY, visible.maxY)
    }

    func testCardStaysInsideANonZeroOriginVisibleFrame() {
        let visible = CGRect(x: -1280, y: 200, width: 1280, height: 800)
        let hit = CGRect(x: -1200, y: 250, width: 40, height: 16)
        let card = CoordinateMapper.cardRect(size: CGSize(width: 320, height: 80),
                                             hit: hit, visible: visible)
        XCTAssertTrue(visible.contains(card))
    }

    // MARK: - v0.3 OCR capture geometry

    private let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

    func testCaptureRegionIsCentredOnThePointer() {
        let window = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        XCTAssertEqual(CoordinateMapper.captureRegion(around: CGPoint(x: 900, y: 500),
                                                      window: window,
                                                      display: display,
                                                      sentenceMode: false),
                       CGRect(x: 500, y: 350, width: 800, height: 300))
    }

    func testSentenceModeUsesTheLargerRegionOnce() {
        let window = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        XCTAssertEqual(CoordinateMapper.captureRegion(around: CGPoint(x: 1_000, y: 600),
                                                      window: window,
                                                      display: display,
                                                      sentenceMode: true),
                       CGRect(x: 400, y: 350, width: 1_200, height: 500))
    }

    func testCaptureRegionIsClippedToTheWindowAndDisplay() {
        let window = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        XCTAssertEqual(CoordinateMapper.captureRegion(around: CGPoint(x: 50, y: 100),
                                                      window: window,
                                                      display: display,
                                                      sentenceMode: false),
                       CGRect(x: 0, y: 0, width: 800, height: 300))
    }

    func testCaptureRegionNeverLeavesTheSourceWindow() {
        // A small window: the region is the window itself, not the design size.
        let window = CGRect(x: 300, y: 400, width: 200, height: 120)
        let region = CoordinateMapper.captureRegion(around: CGPoint(x: 380, y: 460),
                                                    window: window,
                                                    display: display,
                                                    sentenceMode: true)
        XCTAssertEqual(region, window)
    }

    func testCaptureRegionWorksAboveOrLeftOfThePrimaryDisplay() {
        // A display whose origin is negative in both axes, as macOS arranges a
        // screen placed left of and below the primary one.
        let leftDisplay = CGRect(x: -1_920, y: -1_080, width: 1_920, height: 1_080)
        let window = CGRect(x: -1_920, y: -1_080, width: 1_920, height: 1_080)
        let region = CoordinateMapper.captureRegion(around: CGPoint(x: -1_000, y: -500),
                                                    window: window,
                                                    display: leftDisplay,
                                                    sentenceMode: false)
        XCTAssertEqual(region, CGRect(x: -1_400, y: -650, width: 800, height: 300))
    }

    func testCaptureRegionIsNilWhenThePointerIsOutsideTheWindow() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(CoordinateMapper.captureRegion(around: CGPoint(x: 500, y: 500),
                                                    window: window,
                                                    display: display,
                                                    sentenceMode: false))
    }

    func testCapturePixelSizeFollowsTheBackingScale() {
        let region = CGRect(x: 0, y: 0, width: 800, height: 300)
        XCTAssertEqual(CoordinateMapper.capturePixelSize(for: region, scale: 1), CGSize(width: 800, height: 300))
        XCTAssertEqual(CoordinateMapper.capturePixelSize(for: region, scale: 2), CGSize(width: 1_600, height: 600))
    }

    func testCapturePixelSizeIsCappedAndKeepsItsAspectRatio() {
        let region = CGRect(x: 0, y: 0, width: 1_200, height: 500)
        let size = CoordinateMapper.capturePixelSize(for: region, scale: 4)
        XCTAssertLessThanOrEqual(size.width * size.height, 4_000_000)
        XCTAssertEqual(size.width / size.height, 1_200.0 / 500.0, accuracy: 0.01)
        XCTAssertGreaterThan(size.width * size.height, 3_900_000, "the cap must not shrink more than needed")
    }

    func testNormalizedOCRBoxMapsIntoTheCapturedRegion() {
        // Vision reports boxes normalized to the image with a bottom-left origin,
        // which is the same orientation as AppKit's screen space, so no flip is
        // involved: only the capture region's origin and size.
        let region = CGRect(x: 100, y: 200, width: 800, height: 300)
        XCTAssertEqual(CoordinateMapper.imageRectToAppKit(CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                                                          in: region),
                       CGRect(x: 100, y: 200, width: 400, height: 150))
        XCTAssertEqual(CoordinateMapper.imageRectToAppKit(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                                                          in: region),
                       CGRect(x: 500, y: 350, width: 400, height: 150))
    }

    func testWindowLocalCaptureRectUsesTheWindowOrigin() {
        // The capture filter is scoped to one window, whose frame is in
        // top-left-origin screen coordinates.
        let primary = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let axRegion = CoordinateMapper.appKitRectToAX(CGRect(x: 500, y: 350, width: 800, height: 300),
                                                       primaryFrame: primary)
        XCTAssertEqual(axRegion, CGRect(x: 500, y: 430, width: 800, height: 300))
        let windowFrame = CGRect(x: 300, y: 200, width: 1_000, height: 800)
        XCTAssertEqual(CoordinateMapper.windowLocalRect(axRegion, windowFrame: windowFrame),
                       CGRect(x: 200, y: 230, width: 800, height: 300))
    }

    func testWindowLocalCaptureRectIsClampedToTheWindow() {
        let windowFrame = CGRect(x: 300, y: 200, width: 1_000, height: 800)
        let outside = CGRect(x: 0, y: 0, width: 1_600, height: 1_200)
        let local = CoordinateMapper.windowLocalRect(outside, windowFrame: windowFrame)
        XCTAssertEqual(local, CGRect(x: 0, y: 0, width: 1_000, height: 800))
    }
}
