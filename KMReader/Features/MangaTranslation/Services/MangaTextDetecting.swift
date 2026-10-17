import CoreGraphics
import Foundation

nonisolated protocol MangaTextDetecting: Sendable {
  var boxKind: MangaTextBoxKind { get }
  func detect(
    image: CGImage,
    splitMode: PageSplitMode,
    rotation: ReaderRotation,
    borderCropMode: ReaderPageBorderCropMode
  ) throws -> [MangaTextRegion]
}
