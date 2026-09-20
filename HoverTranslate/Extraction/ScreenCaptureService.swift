import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

/// One captured frame plus the screen area it covers.
struct CapturedFrame: Sendable {
    let image: CGImage
    /// AppKit screen coordinates of the captured area.
    let region: CGRect
    /// Pixels per point in the returned image.
    let scale: CGFloat
}

/// v0.3 single-frame capture boundary.
///
/// There is deliberately no streaming member: one call returns at most one
/// frame, and the caller releases it when the query ends or is cancelled. Tests
/// inject a fake, so no test needs the screen or Screen Recording permission.
protocol ScreenCapturing: Sendable {
    /// Captures a small area around the pointer from one window.
    ///
    /// Returns nil when that window, or an area inside it, cannot be resolved. In
    /// that case nothing is captured at all rather than something approximate.
    func captureFrame(point: CGPoint, windowID: CGWindowID, sentenceMode: Bool) async throws -> CapturedFrame?
}

/// ScreenCaptureKit implementation, scoped to a single window.
///
/// The filter is the window the pointer was already confirmed to be over, so a
/// frame can never contain the desktop, another application, a hidden window, or
/// this tool's own card. Permission is never requested here: an unauthorized
/// call throws, so a refusal can never turn into a prompt loop.
struct ScreenCaptureService: ScreenCapturing {
    private static let log = Logger(subsystem: "com.atat.HoverTranslate", category: "capture")

    func captureFrame(point: CGPoint, windowID: CGWindowID, sentenceMode: Bool) async throws -> CapturedFrame? {
        guard CGPreflightScreenCaptureAccess() else { throw ExtractionFailure.permissionDenied }

        let primaryFrame = CGDisplayBounds(CGMainDisplayID())
        let axPoint = CoordinateMapper.appKitToAX(point, primaryFrame: primaryFrame)
        guard let display = Self.display(containing: axPoint) else { return nil }
        let displayBounds = CGDisplayBounds(display)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Only the error domain and code are logged, never any content.
            Self.log.debug("screen content unavailable: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            throw ExtractionFailure.noText
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            Self.log.debug("confirmed window is no longer on screen")
            return nil
        }

        // Clipped to the window and to the display the pointer is on, so the
        // capture can never reach beyond what the user pointed at.
        guard let axRegion = CoordinateMapper.captureRegion(around: axPoint,
                                                            window: window.frame,
                                                            display: displayBounds,
                                                            sentenceMode: sentenceMode) else { return nil }
        // The filter's content is that one window, so the source rect is measured
        // from the window's own origin.
        let sourceRect = CoordinateMapper.windowLocalRect(axRegion, windowFrame: window.frame)
        guard sourceRect.width >= 4, sourceRect.height >= 4 else { return nil }

        let scale = Self.pixelScale(of: display)
        let pixelSize = CoordinateMapper.capturePixelSize(for: sourceRect, scale: scale)

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard image.width == Int(pixelSize.width), image.height == Int(pixelSize.height) else {
            // A frame whose size is not the requested one cannot be mapped to
            // screen points, so it is dropped instead of guessed at.
            Self.log.debug("capture size mismatch: expected \(Int(pixelSize.width), privacy: .public)x\(Int(pixelSize.height), privacy: .public), got \(image.width, privacy: .public)x\(image.height, privacy: .public)")
            return nil
        }
        Self.log.debug("captured \(image.width, privacy: .public)x\(image.height, privacy: .public) px for \(Int(sourceRect.width), privacy: .public)x\(Int(sourceRect.height), privacy: .public) pt, scale \(Double(scale), privacy: .public)")
        return CapturedFrame(image: image,
                             region: CoordinateMapper.axRectToAppKit(axRegion, primaryFrame: primaryFrame),
                             scale: scale)
    }

    /// The active display whose bounds contain the point. CoreGraphics bounds are
    /// the same top-left-origin space as Accessibility, not AppKit's.
    private static func display(containing point: CGPoint) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayBounds($0).contains(point) }
    }

    private static func pixelScale(of display: CGDirectDisplayID) -> CGFloat {
        let bounds = CGDisplayBounds(display)
        guard bounds.width > 0 else { return 1 }
        return CGFloat(CGDisplayPixelsWide(display)) / bounds.width
    }
}
