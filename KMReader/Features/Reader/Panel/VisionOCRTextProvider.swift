//
// VisionOCRTextProvider.swift
//
// `VisionTextProvider` backed by Apple Vision OCR (`VNRecognizeTextRequest`, `.accurate`). Unlike the
// headless rectangle detector it does not hallucinate on art/screentone — it only boxes text it can
// actually read, one box per recognized LINE. We use the geometry only (not the strings): the line
// boxes feed wide-panel readability's split, and their COUNT inside each detector text bubble gives the
// per-bubble line count the readability gate needs. OCR reads horizontal/Latin cleanly but is blind to
// vertical CJK, so an empty result is the routing signal that a page is vertical CJK (see
// `PanelTextReadability`). Runs serialized on a private actor with one reused request.
//

import CoreGraphics
import Foundation
import Vision

/// Wide-panel / bubble-walk readability text source. Normalized [0,1] line boxes, top-left origin.
struct VisionOCRTextProvider: VisionTextProvider {
    var version: String { "vision-ocr-1" }

    func detectText(image: CGImage) async -> [PanelRect] {
        await VisionOCRTextDetector.shared.detectText(image)
    }
}

/// Serializes Vision OCR and reuses one request (Vision requests must not run in parallel). Vision
/// boxes are bottom-left normalized; we flip Y to the top-left convention `PanelRect` uses.
actor VisionOCRTextDetector {
    static let shared = VisionOCRTextDetector()

    private let request: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        return request
    }()
    private let logger = AppLogger(.reader)

    func detectText(_ image: CGImage) -> [PanelRect] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("[PanelOCRText] perform failed: \(error.localizedDescription)")
            return []
        }
        return (request.results ?? []).map { observation in
            let box = observation.boundingBox // bottom-left normalized
            return PanelRect(x: box.minX, y: 1.0 - (box.minY + box.height),
                             width: box.width, height: box.height)
        }
    }
}
