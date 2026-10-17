import Foundation

/// What a detector's box bounds: text-tight boxes (rt_detr) wrap the glyphs,
/// whole-bubble boxes (yolo) wrap the entire bubble. The overlay derives the
/// bubble background and text area geometry from this.
nonisolated enum MangaTextBoxKind: String, Codable, Hashable, Sendable {
  case text
  case bubble
}
