import AppKit
import CoreGraphics
import CoreText
import XCTest
@testable import HoverTranslate

/// v0.3 task 2: the screenshot fallback, measured against images this test
/// draws itself. No real desktop, no user content and no Screen Recording
/// permission is involved: only Vision and the coordinate contract are exercised,
/// which is exactly the part that can be checked deterministically.
final class OCRImageTests: XCTestCase {
    private static let region = CGRect(x: 1_000, y: 500, width: 600, height: 200)

    /// Draws black text on white with a proportional font. The baseline is near
    /// the top of the image, so a flipped box would land in the lower half.
    private func makeImage(lines: [String],
                           size: CGSize = CGSize(width: 600, height: 200),
                           fontSize: CGFloat = 40) -> CGImage {
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("no bitmap context")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        for (index, text) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 20, y: size.height - 60 - CGFloat(index) * (fontSize + 16))
            CTLineDraw(line, context)
        }
        guard let image = context.makeImage() else { fatalError("no image") }
        return image
    }

    private func words(in image: CGImage) throws -> [OCRWord] {
        try VisionTextRecognizer().lines(in: image, region: Self.region).flatMap(\.words)
    }

    func testRecognizerGivesEveryWordItsOwnBoxInsideTheCapturedRegion() throws {
        let recognized = try words(in: makeImage(lines: ["Open Settings"]))
        let texts = recognized.map { $0.text.lowercased() }
        XCTAssertTrue(texts.contains("open"), "recognized: \(texts)")
        XCTAssertTrue(texts.contains("settings"), "recognized: \(texts)")

        let open = try XCTUnwrap(recognized.first { $0.text.lowercased() == "open" })
        let settings = try XCTUnwrap(recognized.first { $0.text.lowercased() == "settings" })
        // Boxes are in screen points inside the captured region, not normalized.
        XCTAssertTrue(Self.region.contains(CGRect(x: open.rect.midX, y: open.rect.midY, width: 0, height: 0)))
        XCTAssertLessThan(open.rect.maxX, settings.rect.minX + 1, "reading order follows the boxes")
        XCTAssertGreaterThan(open.rect.midY, Self.region.midY,
                             "text drawn near the top must not come back flipped")
        XCTAssertGreaterThan(open.rect.width, 0)
        XCTAssertGreaterThan(open.confidence, OCRHitTester.minimumConfidence)
    }

    func testEnglishInsideChineseTextIsFoundAtItsDrawnPosition() async throws {
        let text = "按住 Option 悬停翻译"
        let fontSize: CGFloat = 32
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]))
        let range = (text as NSString).range(of: "Option")
        let left = CTLineGetOffsetForStringIndex(line, range.location, nil)
        let right = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
        // Position comes from the drawing contract, independently of Vision's
        // returned boxes. This catches mapping drift hidden by box-centre tests.
        let point = CGPoint(x: Self.region.minX + 20 + (left + right) / 2,
                            y: Self.region.minY + 140 + fontSize * 0.35)
        let image = makeImage(lines: [text], fontSize: fontSize)
        let capture = StubCapture(frame: CapturedFrame(image: image, region: Self.region, scale: 1))
        let snapshot = try await OCRTextExtractor(capture: capture).extract(
            ExtractionRequest(point: point, sourcePID: 4_242, sourceBundleID: "com.example.reader",
                              sourceWindowID: 77, generation: 1, mode: .word))
        XCTAssertEqual(snapshot.text.lowercased(), "option")
    }

    func testHitTestPicksTheWordUnderThePointerAndNothingInWhitespace() throws {
        let recognized = try words(in: makeImage(lines: ["Open Settings"]))
        let settings = try XCTUnwrap(recognized.first { $0.text.lowercased() == "settings" })
        let onWord = OCRHitTester.pick(point: CGPoint(x: settings.rect.midX, y: settings.rect.midY), words: recognized)
        XCTAssertEqual(onWord?.text.lowercased(), "settings")
        // Well past the last word: whitespace, so there is no answer at all.
        XCTAssertNil(OCRHitTester.pick(point: CGPoint(x: Self.region.maxX - 4, y: settings.rect.midY),
                                       words: recognized))
    }

    func testTwoLinesAreNeverJoinedIntoOneSentence() throws {
        let image = makeImage(lines: ["First line", "Second line"], fontSize: 32)
        let lines = try VisionTextRecognizer().lines(in: image, region: Self.region)
        XCTAssertGreaterThanOrEqual(lines.count, 2, "each visual line is its own recognition")
        let recognized = lines.flatMap(\.words)
        let first = try XCTUnwrap(recognized.first { $0.text.lowercased() == "first" })
        let run = OCRHitTester.lineRun(containing: first, words: recognized)
        XCTAssertFalse(run.contains { $0.text.lowercased() == "second" },
                       "a different line is never part of the run")
    }

    func testExtractorReturnsAPartialSentenceForTheHitLine() async throws {
        let image = makeImage(lines: ["Open Settings"])
        let generator = StubCapture(frame: CapturedFrame(image: image, region: Self.region, scale: 1))
        let extractor = OCRTextExtractor(capture: generator, recognizer: VisionTextRecognizer())
        let settings = try XCTUnwrap(try words(in: image).first { $0.text.lowercased() == "settings" })
        let request = ExtractionRequest(point: CGPoint(x: settings.rect.midX, y: settings.rect.midY),
                                        sourcePID: 4_242,
                                        sourceBundleID: "com.example.reader",
                                        sourceWindowID: 77,
                                        generation: 9,
                                        mode: .sentence)
        let snapshot = try await extractor.extract(request)

        XCTAssertEqual(snapshot.source, .ocr)
        XCTAssertEqual(snapshot.scope, .sentence)
        XCTAssertEqual(snapshot.completeness, .partial, "a recognized line is never claimed as a whole sentence")
        XCTAssertTrue(snapshot.text.lowercased().contains("settings"), "text: \(snapshot.text)")
        XCTAssertEqual(snapshot.generation, 9)
        let frame = try XCTUnwrap(snapshot.wordFrame)
        XCTAssertTrue(Self.region.contains(CGRect(x: frame.midX, y: frame.midY, width: 0, height: 0)),
                      "the reported hit box is in screen points inside the captured region")
    }

    func testExtractorFindsTheWordUnderThePointer() async throws {
        let image = makeImage(lines: ["Open Settings"])
        let generator = StubCapture(frame: CapturedFrame(image: image, region: Self.region, scale: 1))
        let extractor = OCRTextExtractor(capture: generator, recognizer: VisionTextRecognizer())
        let open = try XCTUnwrap(try words(in: image).first { $0.text.lowercased() == "open" })
        let request = ExtractionRequest(point: CGPoint(x: open.rect.midX, y: open.rect.midY),
                                        sourcePID: 4_242,
                                        sourceBundleID: "com.example.reader",
                                        sourceWindowID: 77,
                                        generation: 3,
                                        mode: .word)
        let snapshot = try await extractor.extract(request)
        XCTAssertEqual(snapshot.scope, .word)
        XCTAssertEqual(snapshot.completeness, .complete)
        XCTAssertEqual(snapshot.text.lowercased(), "open")
    }

    func testWhitespaceProducesNoOCRResult() async throws {
        let image = makeImage(lines: ["Open Settings"])
        let generator = StubCapture(frame: CapturedFrame(image: image, region: Self.region, scale: 1))
        let extractor = OCRTextExtractor(capture: generator, recognizer: VisionTextRecognizer())
        let request = ExtractionRequest(point: CGPoint(x: Self.region.maxX - 4, y: Self.region.midY),
                                        sourcePID: 4_242,
                                        sourceBundleID: "com.example.reader",
                                        sourceWindowID: 77,
                                        generation: 4,
                                        mode: .word)
        do {
            _ = try await extractor.extract(request)
            XCTFail("whitespace must not produce a word")
        } catch {
            XCTAssertEqual(error as? ExtractionFailure, .noText)
        }
    }

    /// Without the window the pointer was confirmed to be over, no capture may
    /// happen at all: the fake counts its calls and must stay at zero.
    func testAnUnconfirmedWindowNeverCapturesAnything() async {
        let generator = CountingCapture()
        let extractor = OCRTextExtractor(capture: generator, recognizer: VisionTextRecognizer())
        let request = ExtractionRequest(point: CGPoint(x: 10, y: 10),
                                        sourcePID: 4_242,
                                        sourceBundleID: "com.example.reader",
                                        generation: 1,
                                        mode: .word)
        do {
            _ = try await extractor.extract(request)
            XCTFail("an unowned window must fail")
        } catch {
            XCTAssertEqual(error as? ExtractionFailure, .unknownOwner)
        }
        let calls = await generator.calls
        XCTAssertEqual(calls, 0, "no frame was requested")
    }

    // MARK: - Cross-line sentences (2026-09-19 design)

    private func sentenceRequest(at point: CGPoint, generation: UInt64) -> ExtractionRequest {
        ExtractionRequest(point: point,
                          sourcePID: 4_242,
                          sourceBundleID: "com.example.reader",
                          sourceWindowID: 77,
                          generation: generation,
                          mode: .sentence)
    }

    /// One wrapped paragraph: the two lines are joined, and the sentence is
    /// proven whole because the terminator of the sentence before it is inside
    /// the capture as well.
    func testASentenceWrappedOverTwoLinesIsReadWhole() async throws {
        let image = makeImage(lines: ["First one is here. This sentence wraps",
                                      "onto another line. Third one is here."], fontSize: 32)
        let capture = StubCapture(frame: CapturedFrame(image: image, region: Self.region, scale: 1))
        let extractor = OCRTextExtractor(capture: capture, recognizer: VisionTextRecognizer())
        let wraps = try XCTUnwrap(try words(in: image).first { $0.text.lowercased() == "wraps" })

        let snapshot = try await extractor.extract(sentenceRequest(at: CGPoint(x: wraps.rect.midX,
                                                                              y: wraps.rect.midY),
                                                                  generation: 11))

        XCTAssertEqual(snapshot.text.lowercased(), "this sentence wraps onto another line.")
        XCTAssertEqual(snapshot.scope, .sentence)
        XCTAssertEqual(snapshot.completeness, .complete)
        let frame = try XCTUnwrap(snapshot.wordFrame)
        XCTAssertGreaterThan(frame.height, wraps.rect.height, "the anchor covers words on both lines")
    }

    /// The capture's own top edge proves nothing about the paragraph behind it,
    /// so a sentence that starts there is never claimed as a whole one.
    func testASentenceStartingAtTheCaptureEdgeIsPartial() async throws {
        let image = makeImage(lines: ["This sentence wraps", "onto another line."], fontSize: 32)
        let capture = StubCapture(frame: CapturedFrame(image: image, region: Self.region, scale: 1))
        let extractor = OCRTextExtractor(capture: capture, recognizer: VisionTextRecognizer())
        let wraps = try XCTUnwrap(try words(in: image).first { $0.text.lowercased() == "wraps" })

        let snapshot = try await extractor.extract(sentenceRequest(at: CGPoint(x: wraps.rect.midX,
                                                                              y: wraps.rect.midY),
                                                                  generation: 12))

        XCTAssertEqual(snapshot.text.lowercased(), "this sentence wraps onto another line.",
                       "the whole wrapped sentence is still the text, not one line of it")
        XCTAssertEqual(snapshot.completeness, .partial)
    }

    /// The assembly and the anchor, with scripted recognition so nothing here
    /// depends on Vision's quality.
    func testTheAnchorCoversEveryWordOfTheJoinedLines() async throws {
        let upper = [word("First", 1_000, 662, 40), word("one.", 1_044, 662, 44),
                     word("This", 1_092, 662, 40), word("sentence", 1_136, 662, 80),
                     word("wraps", 1_220, 662, 50)]
        let lower = [word("onto", 1_000, 640, 40), word("another", 1_044, 640, 70),
                     word("line.", 1_118, 640, 40)]
        let lines = [OCRLine(text: "First one. This sentence wraps", words: upper),
                     OCRLine(text: "onto another line.", words: lower)]
        let capture = StubCapture(frame: CapturedFrame(image: makeImage(lines: []), region: Self.region, scale: 1))
        let extractor = OCRTextExtractor(capture: capture, recognizer: StubRecognizer(scripted: lines))

        let snapshot = try await extractor.extract(sentenceRequest(at: CGPoint(x: upper[4].rect.midX,
                                                                              y: upper[4].rect.midY),
                                                                  generation: 13))

        XCTAssertEqual(snapshot.scope, .sentence)
        XCTAssertEqual(snapshot.source, .ocr)
        XCTAssertEqual(snapshot.text, "This sentence wraps onto another line.")
        XCTAssertEqual(snapshot.completeness, .complete)
        // The union of both lines' words: 1_000…1_270 across, 640…682 up.
        XCTAssertEqual(snapshot.wordFrame, CGRect(x: 1_000, y: 640, width: 270, height: 42))
    }

    private func word(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> OCRWord {
        OCRWord(text: text, rect: CGRect(x: x, y: y, width: width, height: 20), confidence: 0.99)
    }
}

/// Scripted recognition: the geometry rules are checked without Vision.
private struct StubRecognizer: OCRRecognizing {
    let scripted: [OCRLine]
    func lines(in image: CGImage, region: CGRect) throws -> [OCRLine] { scripted }
}

private struct StubCapture: ScreenCapturing {
    let frame: CapturedFrame?
    func captureFrame(point: CGPoint, windowID: CGWindowID, sentenceMode: Bool) async throws -> CapturedFrame? {
        frame
    }
}

private actor CountingCapture: ScreenCapturing {
    private(set) var calls = 0
    func captureFrame(point: CGPoint, windowID: CGWindowID, sentenceMode: Bool) async throws -> CapturedFrame? {
        calls += 1
        return nil
    }
}
