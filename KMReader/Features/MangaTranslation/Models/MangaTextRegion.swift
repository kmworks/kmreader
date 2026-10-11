import CoreGraphics
import Foundation

nonisolated struct MangaTextRegion: Identifiable, Codable, Hashable, Sendable {
  let id: Int
  let label: Int
  let score: Float
  let sourceBox: CGRect
  let box: CGRect
  let text: String
  var translatedText: String?
  let orientation: MangaTextOrientation
}
