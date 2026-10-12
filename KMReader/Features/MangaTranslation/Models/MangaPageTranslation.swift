import Foundation

nonisolated struct MangaPageTranslation: Codable, Hashable, Sendable {
  let key: MangaTranslationPageKey
  let regions: [MangaTextRegion]
  let status: MangaTranslationStatus
  let createdAt: Date

  var isTranslated: Bool { status == .translated }
}
