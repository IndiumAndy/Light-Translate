import XCTest
@testable import HoverTranslate

/// v0.3 task 2: when a screenshot may be taken at all.
///
/// Security refusals are never a reason to capture the screen; only a technical
/// limitation is, and only with the user's own switch, a granted capture
/// permission and a confirmed source window.
final class OCRFallbackPolicyTests: XCTestCase {
    func testSecurityDenialNeverBecomesScreenshotFallback() {
        XCTAssertFalse(OCRFallbackPolicy.allows(.blockedSensitive,
            userEnabled: true, captureAuthorized: true, sourceConfirmed: true))
        XCTAssertFalse(OCRFallbackPolicy.allows(.permissionDenied,
            userEnabled: true, captureAuthorized: true, sourceConfirmed: true))
        XCTAssertFalse(OCRFallbackPolicy.allows(.unknownOwner,
            userEnabled: true, captureAuthorized: true, sourceConfirmed: false))
    }

    func testUnsupportedTextMayFallbackOnlyWhenAuthorized() {
        XCTAssertTrue(OCRFallbackPolicy.allows(.notSupported,
            userEnabled: true, captureAuthorized: true, sourceConfirmed: true))
        XCTAssertFalse(OCRFallbackPolicy.allows(.notSupported,
            userEnabled: false, captureAuthorized: true, sourceConfirmed: true))
    }

    func testTechnicalFailuresNeedAllThreeConditions() {
        for failure in [ExtractionFailure.noText, .notSupported, .positionUnresolved] {
            XCTAssertTrue(OCRFallbackPolicy.allows(failure, userEnabled: true,
                                                   captureAuthorized: true, sourceConfirmed: true))
            XCTAssertFalse(OCRFallbackPolicy.allows(failure, userEnabled: false,
                                                    captureAuthorized: true, sourceConfirmed: true))
            XCTAssertFalse(OCRFallbackPolicy.allows(failure, userEnabled: true,
                                                    captureAuthorized: false, sourceConfirmed: true))
            XCTAssertFalse(OCRFallbackPolicy.allows(failure, userEnabled: true,
                                                    captureAuthorized: true, sourceConfirmed: false))
        }
    }

    func testPolicyFailuresNeverReachTheScreen() {
        for failure in [ExtractionFailure.appNotAllowed, .timeout, .blockedSensitive,
                        .permissionDenied, .unknownOwner] {
            XCTAssertFalse(OCRFallbackPolicy.allows(failure, userEnabled: true,
                                                    captureAuthorized: true, sourceConfirmed: true),
                           "\(failure) must never start a capture")
        }
    }

    func testRateLimiterAllowsAtMostOneCapturePerInterval() {
        var limiter = OCRRateLimiter()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(limiter.takeSlot(now: start))
        XCTAssertFalse(limiter.takeSlot(now: start.addingTimeInterval(0.4)))
        XCTAssertFalse(limiter.takeSlot(now: start.addingTimeInterval(0.79)))
        // Just past the interval; the exact boundary is not a meaningful test on
        // a floating-point Date.
        XCTAssertTrue(limiter.takeSlot(now: start.addingTimeInterval(0.81)))
        XCTAssertTrue(limiter.takeSlot(now: start.addingTimeInterval(10)))
    }
}
