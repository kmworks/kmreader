import CoreGraphics
import Foundation

enum MangaTextOrientation: String, Codable, Hashable, Sendable {
  case unknown
  case horizontal
  case vertical

  // Detector labels usually carry no orientation metadata; a box taller
  // than wide is the standard vertical-typesetting signal.
  static func infer(from box: CGRect) -> MangaTextOrientation {
    box.height > box.width ? .vertical : .horizontal
  }
}
