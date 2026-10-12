import Foundation

nonisolated struct MangaPageTranslation: Codable, Hashable, Sendable {
  let key: MangaTranslationPageKey
  let regions: [MangaTextRegion]
  let status: MangaTranslationStatus
  let targetLanguage: String
  let createdAt: Date

  var isTranslated: Bool { status == .translated }

  init(
    key: MangaTranslationPageKey,
    regions: [MangaTextRegion],
    status: MangaTranslationStatus,
    targetLanguage: String,
    createdAt: Date
  ) {
    self.key = key
    self.regions = regions
    self.status = status
    self.targetLanguage = targetLanguage
    self.createdAt = createdAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(MangaTranslationPageKey.self, forKey: .key)
    regions = try container.decode([MangaTextRegion].self, forKey: .regions)
    status = try container.decode(MangaTranslationStatus.self, forKey: .status)
    // Rows cached before the field existed fall back to an unknown
    // language, which keeps their rendering horizontal.
    targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? ""
    createdAt = try container.decode(Date.self, forKey: .createdAt)
  }
}
