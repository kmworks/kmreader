import CoreGraphics
import Foundation
import Vision

nonisolated enum PageOCRService {
  @available(iOS 18.0, macOS 15.0, tvOS 18.0, *)
  static func recognizeLines(in image: CGImage) async -> [RecognizedTextLine] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "zh-Hans", "zh-Hant", "ko-KR", "en-US"].map {
      Locale.Language(identifier: $0)
    }

    let observations: [RecognizedTextObservation]
    do {
      observations = try await request.perform(on: image)
    } catch {
      AppLogger(.reader).error("❌ [Translate] OCR failed: \(error)")
      return []
    }

    let pageWidth = CGFloat(image.width)
    let pageHeight = CGFloat(image.height)

    return observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else {
        return nil
      }
      // Isolated short runs of digits/latin/punct are decorative art misreads
      // ("1.00.", "Od"), never dialogue; CJK text always passes.
      let text = candidate.string
      guard containsCJK(text) || text.filter(\.isLetter).count >= 3 else { return nil }
      let box = observation.boundingBox
      let width = box.width * pageWidth
      let height = box.height * pageHeight
      guard min(width, height) >= 8 else { return nil }
      let rect = CGRect(
        x: box.origin.x * pageWidth,
        y: (1 - box.origin.y - box.height) * pageHeight,
        width: width,
        height: height
      )
      return RecognizedTextLine(rect: rect, text: text)
    }
  }

  private static func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0x3040...0x30FF).contains(scalar.value)  // kana
        || (0x4E00...0x9FFF).contains(scalar.value)  // CJK ideographs
        || (0xAC00...0xD7AF).contains(scalar.value)  // hangul syllables
    }
  }
}
