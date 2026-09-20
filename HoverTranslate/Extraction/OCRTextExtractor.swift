import AppKit
import CoreGraphics
import Foundation
import Vision
import os

/// One recognized text line and its words, in screen points.
struct OCRLine: Equatable, Sendable {
    let text: String
    let words: [OCRWord]
}

/// The local multi-line text assembled around one recognized hit.
///
/// Recognition returns words with real boxes; the text and the word ranges are
/// built here, so a sentence resolved inside that text can be mapped back to the
/// words it covers — which is what the card anchors on.
struct OCRContext: Equatable, Sendable {
    /// The lines of the hit's block, joined with line breaks. A single break is
    /// folded again by the resolver, so what is shown is one line.
    let text: String
    let words: [OCRWord]
    /// The range each word occupies in `text`, in the same order as `words`.
    let ranges: [NSRange]

    /// The bounded block around one hit, or nil when nothing usable surrounds it.
    static func around(hit: OCRWord, lines: [OCRLine]) -> OCRContext? {
        assemble(OCRHitTester.contextLines(containing: hit, lines: lines))
    }

    /// The range one recognized word occupies in `text`.
    func range(of word: OCRWord) -> NSRange? {
        zip(words, ranges).first { $0.0 == word }?.1
    }

    /// The words a resolved sentence covers, in reading order.
    func words(in range: NSRange) -> [OCRWord] {
        zip(words, ranges)
            .filter { $0.1.location < range.location + range.length
                && range.location < $0.1.location + $0.1.length }
            .map(\.0)
    }

    /// The context as one bounded text. The 2000-unit ceiling is the same one
    /// the Accessibility path reads, and a line that would cross it is dropped
    /// rather than cut in half.
    private static func assemble(_ runs: [[OCRWord]]) -> OCRContext? {
        var text = ""
        var words: [OCRWord] = []
        var ranges: [NSRange] = []
        assembling: for run in runs {
            var isFirstInLine = true
            for word in run {
                let piece = word.text + word.trailing
                let separator = text.isEmpty ? "" : (isFirstInLine ? "\n" : " ")
                let length = (text as NSString).length
                guard length + (separator as NSString).length + (piece as NSString).length
                    <= SentenceResolver.maximumWindowLength else { break assembling }
                text += separator + piece
                ranges.append(NSRange(location: length + (separator as NSString).length,
                                      length: (piece as NSString).length))
                words.append(word)
                isFirstInLine = false
            }
        }
        guard !words.isEmpty else { return nil }
        return OCRContext(text: text, words: words, ranges: ranges)
    }
}

/// v0.3 recognizer boundary. The real implementation is local Vision; a fake is
/// only ever used to script the coordinator, so no test depends on OCR quality.
protocol OCRRecognizing: Sendable {
    /// Words whose boxes are already converted into the screen region the image
    /// covers.
    func lines(in image: CGImage, region: CGRect) throws -> [OCRLine]
}

/// Local, offline text recognition.
///
/// Per-word boxes come from the recognizer's own range geometry; they are never
/// derived by dividing a line evenly, which would be wrong for any proportional
/// font. Confidence is reported per candidate, which is what the recognizer
/// offers: the classic Vision API has no per-substring confidence.
struct VisionTextRecognizer: OCRRecognizing {
    func lines(in image: CGImage, region: CGRect) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string
            var found: [(text: String, range: Range<String.Index>, box: CGRect)] = []
            string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) { substring, range, _, _ in
                guard let substring, !substring.isEmpty,
                      let box = try? candidate.boundingBox(for: range) else { return }
                found.append((substring, range, box.boundingBox))
            }
            // Word enumeration deliberately leaves punctuation out. What sits
            // between two words is kept as that word's trailing text, so the
            // assembled sentence reads like the line the recognizer saw.
            let words = found.enumerated().map { index, word -> OCRWord in
                let end = index + 1 < found.count ? found[index + 1].range.lowerBound : string.endIndex
                return OCRWord(text: word.text,
                               rect: CoordinateMapper.imageRectToAppKit(word.box, in: region),
                               confidence: candidate.confidence,
                               trailing: String(string[word.range.upperBound..<end])
                                   .trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard !words.isEmpty else { return nil }
            return OCRLine(text: string, words: words)
        }
    }
}

/// v0.3: the screenshot fallback, used only when Accessibility reports a
/// technical limitation and the policy, the user's switch and the capture
/// permission all allow it.
///
/// Recognition runs on its own serial queue: the coordinator is main-actor
/// isolated, and a synchronous Vision call there would block the interface.
struct OCRTextExtractor: TextExtracting {
    /// Category-only diagnostics: role-free and content-free by construction.
    private static let log = Logger(subsystem: "com.atat.HoverTranslate", category: "ocr")
    private let capture: ScreenCapturing
    private let recognizer: OCRRecognizing
    private let queue = DispatchQueue(label: "com.atat.HoverTranslate.ocr", qos: .userInitiated)

    init(capture: ScreenCapturing = ScreenCaptureService(),
         recognizer: OCRRecognizing = VisionTextRecognizer()) {
        self.capture = capture
        self.recognizer = recognizer
    }

    func extract(_ request: ExtractionRequest) async throws -> ExtractionSnapshot {
        guard let windowID = request.sourceWindowID, windowID != 0 else {
            // Without the confirmed window there is no area that may be captured.
            throw ExtractionFailure.unknownOwner
        }
        guard let frame = try await capture.captureFrame(point: request.point,
                                                        windowID: windowID,
                                                        sentenceMode: request.mode == .sentence) else {
            throw ExtractionFailure.noText
        }

        let queue = self.queue
        let recognizer = self.recognizer
        let lines: [OCRLine] = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try recognizer.lines(in: frame.image, region: frame.region) })
            }
        }

        let words = lines.flatMap(\.words)
        guard let hit = OCRHitTester.pick(point: request.point, words: words) else {
            // Whitespace, a low-confidence guess or a position outside every word
            // box: there is no answer rather than a nearby one.
            throw ExtractionFailure.noText
        }

        if request.mode == .sentence {
            // 2026-09-19: the lines of one local paragraph are assembled first
            // and resolved by the same boundary rules the Accessibility path
            // uses. Only when that proves no sentence at all does the single
            // recognized line remain, marked partial as it always was.
            if let resolved = sentenceSnapshot(hit: hit, lines: lines, request: request) {
                return resolved
            }
            guard let line = lines.first(where: { $0.words.contains(hit) }) else {
                throw ExtractionFailure.noText
            }
            let run = OCRHitTester.lineRun(containing: hit, words: line.words)
            guard !run.isEmpty else { throw ExtractionFailure.noText }
            Self.log.debug("sentence boundary=line-only")
            return snapshot(text: run.map(\.text).joined(separator: " "),
                            scope: .sentence,
                            completeness: .partial,
                            frame: OCRHitTester.boundingBox(run),
                            request: request)
        }

        return snapshot(text: hit.text, scope: .word, completeness: .complete, frame: hit.rect, request: request)
    }

    /// The sentence around the hit, resolved on the assembled block.
    ///
    /// Nil when the block proves no sentence at all, which leaves the caller its
    /// existing single-line fallback. The capture's own edges prove nothing, so
    /// a sentence starting at them is partial by construction.
    private func sentenceSnapshot(hit: OCRWord,
                                  lines: [OCRLine],
                                  request: ExtractionRequest) -> ExtractionSnapshot? {
        guard let context = OCRContext.around(hit: hit, lines: lines),
              let offset = context.range(of: hit)?.location,
              let resolution = SentenceResolver.resolve(in: .fragment(context.text),
                                                        atUTF16Offset: offset) else { return nil }
        let covered = context.words(in: resolution.originalRange)
        guard !covered.isEmpty else { return nil }
        // Category only: the boundary decision, never the text it was made on.
        Self.log.debug("sentence boundary=\(resolution.boundary.rawValue, privacy: .public)")
        return snapshot(text: resolution.text,
                        scope: .sentence,
                        completeness: resolution.completeness,
                        frame: OCRHitTester.boundingBox(covered),
                        request: request)
    }

    private func snapshot(text: String,
                          scope: ExtractionScope,
                          completeness: ExtractionCompleteness,
                          frame: CGRect,
                          request: ExtractionRequest) -> ExtractionSnapshot {
        ExtractionSnapshot(text: text,
                           context: nil,
                           scope: scope,
                           completeness: completeness,
                           source: .ocr,
                           sourcePID: request.sourcePID,
                           sourceBundleID: request.sourceBundleID,
                           wordFrame: frame,
                           generation: request.generation)
    }
}
