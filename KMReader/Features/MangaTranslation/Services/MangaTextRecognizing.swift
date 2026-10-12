import CoreGraphics
import Foundation

nonisolated protocol MangaTextRecognizing: Sendable {
  func recognize(crops regions: [MangaTextRegion], image: CGImage) throws -> [MangaTextRegion]
}
