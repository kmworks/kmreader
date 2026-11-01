//
// PanelPagePresentation.swift
//
//

import CoreGraphics
import Foundation

/// How a page is shown to the reader: the reading direction that orders its panels, plus the
/// rotation and border crop that turn the original page into the displayed one. Panels are
/// detected and ordered on the original page, then mapped into the displayed page, so the story
/// order never depends on how the page happens to be rotated.
nonisolated struct PanelPagePresentation: Hashable, Sendable {
  let direction: ReadingDirection
  let rotation: ReaderRotation
  let borderCropMode: ReaderPageBorderCropMode

  /// True when the displayed page differs from the original image.
  var transformsPage: Bool {
    rotation != .none || borderCropMode != .disabled
  }

  /// Maps a sequence detected on the original `image` into displayed-page coordinates. A panel
  /// the border crop trims away entirely is dropped; a sequence left with nothing becomes `.empty`.
  func displayed(_ sequence: PanelSequence, in image: CGImage) -> PanelSequence {
    guard transformsPage else { return sequence }
    let cropRect = PreparedReaderPageGeometry.cropRect(
      for: image,
      rotation: rotation,
      borderCropMode: borderCropMode
    )
    func map(_ rect: PanelRect) -> PanelRect? {
      let displayed = PreparedReaderPageGeometry.normalizedRect(
        for: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
        in: image,
        splitMode: .none,
        rotation: rotation,
        cropRect: cropRect
      )
      guard PreparedReaderPageGeometry.isVisible(displayed) else { return nil }
      return PanelRect(x: displayed.minX, y: displayed.minY, width: displayed.width, height: displayed.height)
    }
    switch sequence {
    case .empty:
      return .empty
    case .panels(let rects):
      let mapped = rects.compactMap(map)
      return mapped.isEmpty ? .empty : .panels(mapped)
    case .splash(let rect):
      return map(rect).map(PanelSequence.splash) ?? .empty
    }
  }
}
