//
// VisionOCRTextDetector.swift
//
//

import CoreGraphics
import Foundation
import Vision

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
      let box = observation.boundingBox  // bottom-left normalized
      return PanelRect(
        x: box.minX, y: 1.0 - (box.minY + box.height),
        width: box.width, height: box.height)
    }
  }
}
