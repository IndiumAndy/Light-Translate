import CoreGraphics
import Foundation

/// Converts between AppKit screen points (origin at the bottom-left of the
/// primary display) and Accessibility screen points (origin at the top-left of
/// the same primary display).
///
/// Both spaces are measured in screen points, so no backing-scale conversion
/// happens here. The primary display frame is always the reference, never the
/// screen of the current key window.
enum CoordinateMapper {
    static func appKitToAX(_ point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrame.maxY - point.y)
    }

    static func axToAppKit(_ point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrame.maxY - point.y)
    }

    static func appKitRectToAX(_ rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryFrame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    static func axRectToAppKit(_ rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryFrame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - OCR capture geometry

    /// Design initial sizes, not measured limits. The sentence region is used
    /// once; there is no unbounded growth if recognition finds nothing.
    static let capturePointSize = CGSize(width: 800, height: 300)
    static let captureSentenceSize = CGSize(width: 1_200, height: 500)
    static let maximumCapturePixels: CGFloat = 4_000_000

    /// The area a single frame may cover around the pointer.
    ///
    /// Clipped to the source window and the display it sits on, so a capture can
    /// never reach a hidden window, another application, or the desktop. Returns
    /// nil when the pointer is not inside both, in which case nothing is taken.
    static func captureRegion(around point: CGPoint,
                              window: CGRect,
                              display: CGRect,
                              sentenceMode: Bool) -> CGRect? {
        let allowed = window.intersection(display)
        guard !allowed.isNull,
              allowed.width > 1, allowed.height > 1,
              allowed.contains(point) else { return nil }
        let desired = sentenceMode ? captureSentenceSize : capturePointSize
        let size = CGSize(width: min(desired.width, allowed.width),
                          height: min(desired.height, allowed.height))
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        origin.x = min(max(origin.x, allowed.minX), allowed.maxX - size.width)
        origin.y = min(max(origin.y, allowed.minY), allowed.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    /// The pixel size to ask the capture API for, with the design's 4,000,000
    /// pixel ceiling applied by uniform downscaling rather than by cropping.
    static func capturePixelSize(for region: CGRect, scale: CGFloat) -> CGSize {
        let scale = max(scale, 1)
        var width = (region.width * scale).rounded()
        var height = (region.height * scale).rounded()
        let pixels = width * height
        if pixels > maximumCapturePixels {
            let factor = (maximumCapturePixels / pixels).squareRoot()
            width = (width * factor).rounded(.down)
            height = (height * factor).rounded(.down)
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    /// A recognizer box, normalized to the captured image, as an AppKit screen
    /// rect.
    ///
    /// Vision measures from the bottom-left of the image, and AppKit measures
    /// from the bottom-left of the capture region it took, so the two share an
    /// orientation: only the region's origin and size are applied, and no flip
    /// happens here.
    static func imageRectToAppKit(_ rect: CGRect, in captureRegion: CGRect) -> CGRect {
        CGRect(x: captureRegion.minX + rect.minX * captureRegion.width,
               y: captureRegion.minY + rect.minY * captureRegion.height,
               width: rect.width * captureRegion.width,
               height: rect.height * captureRegion.height)
    }

    /// A rect in top-left-origin screen points as a rect inside one window.
    ///
    /// The window is the capture filter's content, so the source rect is
    /// measured from the window's own origin and is clamped to it.
    static func windowLocalRect(_ rect: CGRect, windowFrame: CGRect) -> CGRect {
        let local = CGRect(x: rect.minX - windowFrame.minX,
                           y: rect.minY - windowFrame.minY,
                           width: rect.width,
                           height: rect.height)
        return local.intersection(CGRect(origin: .zero, size: windowFrame.size))
    }

    /// Places a card near a hit rectangle without covering it and without
    /// leaving the visible frame of the screen the hit is on.
    static func cardRect(size: CGSize,
                         hit: CGRect,
                         visible: CGRect,
                         gap: CGFloat = 8) -> CGRect {
        var origin = CGPoint(x: hit.minX, y: hit.minY - gap - size.height)
        if origin.y < visible.minY {
            origin.y = hit.maxY + gap
        }
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        origin.x = min(max(origin.x, visible.minX), maxX)
        origin.y = min(max(origin.y, visible.minY), maxY)
        return CGRect(origin: origin, size: size)
    }
}
