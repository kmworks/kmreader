import CoreGraphics
import CoreML
import Foundation

nonisolated enum MangaOCRPreprocessing {
  case stretch
  case letterbox

  func pixelValues(_ image: CGImage) throws -> MLMultiArray {
    switch self {
    case .stretch:
      return try MangaInferenceUtilities.pixelValues(image, width: 224, height: 224, normalize: true)
    case .letterbox:
      return try MangaInferenceUtilities.pixelValuesLetterbox(image, size: 224)
    }
  }
}
