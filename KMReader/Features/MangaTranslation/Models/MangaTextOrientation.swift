import CoreGraphics
import Foundation

nonisolated enum MangaTextOrientation: String, Codable, Hashable, Sendable {
  case unknown
  case horizontal
  case vertical

  // Detector labels usually carry no orientation metadata; a box taller
  // than wide is the standard vertical-typesetting signal. Normalized
  // boxes must be compared in physical units: a portrait page shrinks
  // normalized heights, hiding near-square vertical bubbles.
  static func infer(from box: CGRect, displaySize: CGSize) -> MangaTextOrientation {
    box.height * displaySize.height > box.width * displaySize.width ? .vertical : .horizontal
  }

  // Regions cached before physical inference existed carry no display
  // size; the normalized comparison stays conservative on purpose —
  // only unambiguous vertical boxes trigger.
  static func infer(from box: CGRect) -> MangaTextOrientation {
    box.height > box.width ? .vertical : .horizontal
  }
}
