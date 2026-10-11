import Foundation

nonisolated struct MangaTextSegment: Codable, Hashable, Sendable {
  let id: Int
  let text: String
}
