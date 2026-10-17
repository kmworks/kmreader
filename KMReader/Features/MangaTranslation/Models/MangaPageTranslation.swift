import Foundation

nonisolated struct MangaPageTranslation: Codable, Hashable, Sendable {
  let key: MangaTranslationPageKey
  let regions: [MangaTextRegion]
  let status: MangaTranslationStatus
  let targetLanguage: String
  let boxKind: MangaTextBoxKind
  let createdAt: Date

  var isTranslated: Bool { status == .translated }

  /// Terminal for caching: a completed translation, or a page that provably
  /// has no text. Anything else (e.g. provider failures) must retry.
  var isFinalized: Bool {
    (isTranslated && !regions.isEmpty) || status == .recognitionOnly(.noText)
  }

  init(
    key: MangaTranslationPageKey,
    regions: [MangaTextRegion],
    status: MangaTranslationStatus,
    targetLanguage: String,
    boxKind: MangaTextBoxKind,
    createdAt: Date
  ) {
    self.key = key
    self.regions = regions
    self.status = status
    self.targetLanguage = targetLanguage
    self.boxKind = boxKind
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
    // Rows cached before the field existed fall back to text-tight geometry:
    // the rounded rectangle hugs the box for either kind, and the small-inset
    // text area still lands inside the bubble.
    boxKind = try container.decodeIfPresent(MangaTextBoxKind.self, forKey: .boxKind) ?? .text
    createdAt = try container.decode(Date.self, forKey: .createdAt)
  }
}
