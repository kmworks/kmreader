import Foundation

/// User-selected bubble background shape; `MangaBubbleBackground` derives the
/// background and text geometry from it.
nonisolated enum MangaBubbleShape: String, Codable, Hashable, Sendable {
  case ellipse
  case roundedRect
}
