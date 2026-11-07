import Vision
import UIKit

/// A recognized, tappable Chinese word positioned on the frozen frame.
struct OCRWord: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// Normalized Vision rect (origin bottom-left) in the upright image's space.
    let boundingBox: CGRect
    /// The sentence this word appears in, for showing its translation.
    let sentence: SentenceRef?
}

/// The full result of recognizing one captured frame.
struct OCRResult: Identifiable {
    let id = UUID()
    let image: UIImage          // upright, downscaled for display; boxes are normalized
    let words: [OCRWord]
    let sentences: [String]

    var hasChinese: Bool { !words.isEmpty }

    static func empty(_ image: UIImage) -> OCRResult {
        OCRResult(image: image, words: [], sentences: [])
    }
}

enum TextRecognizer {
    /// Recognizes Chinese text in `image`, segments each line into words, and
    /// resolves a bounding box per word. Runs off the main actor.
    static func recognize(in image: UIImage, dictionary: ChineseDictionary) async -> OCRResult {
        await dictionary.ensureLoaded()
        // Only this smaller copy outlives recognition; the full-resolution photo is
        // released when the caller drops it. Vision reads the original pixels with
        // their orientation tag, so no second full-size upright copy is made.
        let display = image.uprightDownscaled(maxPixelDimension: 4032)
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let aspect = display.size.height > 0 ? display.size.width / display.size.height : 1

        guard let cgImage = image.cgImage else { return .empty(display) }

        return await withCheckedContinuation { (cont: CheckedContinuation<OCRResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant"]
                request.usesLanguageCorrection = true
                // Default ignores text shorter than 1/32 of the image height.
                request.minimumTextHeight = 0.01

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: .empty(display))
                    return
                }

                var lines: [RecognizedLine] = []
                var found: [(text: String, box: CGRect, line: Int, offset: Int)] = []

                for observation in request.results ?? [] {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let lineText = candidate.string
                    let line = lines.count
                    lines.append(RecognizedLine(text: lineText, box: observation.boundingBox))

                    for segment in dictionary.segment(lineText) where segment.isWord {
                        let box = (try? candidate.boundingBox(for: segment.range))?.boundingBox
                            ?? estimatedBox(for: segment.range, in: lineText, lineBox: observation.boundingBox)
                        let offset = lineText.distance(from: lineText.startIndex, to: segment.range.lowerBound)
                        found.append((segment.text, box, line, offset))
                    }
                }

                let map = TextLayout.sentenceMap(from: lines, imageAspect: aspect)
                let words = found.map { word in
                    OCRWord(text: word.text, boundingBox: word.box,
                            sentence: map.sentence(line: word.line, characterOffset: word.offset,
                                                   length: word.text.count))
                }
                cont.resume(returning: OCRResult(image: display, words: words, sentences: map.sentences))
            }
        }
    }

    /// Fallback when Vision has no box for a substring: Chinese characters are
    /// close to fixed-width, so place the word proportionally along its line
    /// rather than letting it cover (and steal taps from) the whole line.
    private static func estimatedBox(for range: Range<String.Index>, in line: String, lineBox: CGRect) -> CGRect {
        let total = CGFloat(max(line.count, 1))
        let start = CGFloat(line.distance(from: line.startIndex, to: range.lowerBound))
        let length = CGFloat(line.distance(from: range.lowerBound, to: range.upperBound))
        return CGRect(
            x: lineBox.minX + lineBox.width * start / total,
            y: lineBox.minY,
            width: lineBox.width * length / total,
            height: lineBox.height
        )
    }
}

extension UIImage {
    /// An upright (`.up`) copy whose longest side is at most `maxPixelDimension`.
    /// Vision's normalized boxes map onto it unchanged.
    func uprightDownscaled(maxPixelDimension: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let ratio = min(1, maxPixelDimension / max(pixelSize.width, pixelSize.height))
        let target = CGSize(width: (pixelSize.width * ratio).rounded(),
                            height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
