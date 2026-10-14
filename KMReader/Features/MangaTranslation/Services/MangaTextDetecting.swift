import CoreGraphics
import Foundation

nonisolated protocol MangaTextDetecting: Sendable {
  func detect(
    image: CGImage,
    splitMode: PageSplitMode,
    rotation: ReaderRotation,
    borderCropMode: ReaderPageBorderCropMode
  ) throws -> [MangaTextRegion]
}
