import CoreGraphics
import Foundation

nonisolated protocol MangaTextRecognizing {
  func recognize(crops regions: [MangaTextRegion], image: CGImage) throws -> [MangaTextRegion]
}
