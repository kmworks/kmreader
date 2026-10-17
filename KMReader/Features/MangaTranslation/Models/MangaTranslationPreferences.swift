import Foundation

nonisolated struct MangaTranslationPreferences: Codable, Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var selectedProviderID: String
  var sourceLanguage: String
  var targetLanguage: String
  var includeMetadata: Bool
  var showTranslation: Bool
  var textDirection: MangaTranslationTextDirection
  var bubbleShape: MangaBubbleShape

  init(
    selectedProviderID: String = "",
    sourceLanguage: String = MangaTranslationLanguage.defaultSource,
    targetLanguage: String = "",
    includeMetadata: Bool = false,
    showTranslation: Bool = true,
    textDirection: MangaTranslationTextDirection = .auto,
    bubbleShape: MangaBubbleShape = .ellipse
  ) {
    self.selectedProviderID = selectedProviderID
    self.sourceLanguage = sourceLanguage
    self.targetLanguage = targetLanguage
    self.includeMetadata = includeMetadata
    self.showTranslation = showTranslation
    self.textDirection = textDirection
    self.bubbleShape = bubbleShape
  }

  init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8),
      let decoded = RawCodableStore.decode(Self.self, from: data)
    else {
      return nil
    }
    self = decoded
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      selectedProviderID: try container.decodeIfPresent(String.self, forKey: .selectedProviderID) ?? "",
      sourceLanguage: try container.decodeIfPresent(String.self, forKey: .sourceLanguage)
        ?? MangaTranslationLanguage.defaultSource,
      targetLanguage: try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "",
      includeMetadata: try container.decodeIfPresent(Bool.self, forKey: .includeMetadata) ?? false,
      showTranslation: try container.decodeIfPresent(Bool.self, forKey: .showTranslation) ?? true,
      textDirection: try container.decodeIfPresent(
        MangaTranslationTextDirection.self, forKey: .textDirection) ?? .auto,
      bubbleShape: try container.decodeIfPresent(MangaBubbleShape.self, forKey: .bubbleShape) ?? .ellipse
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(selectedProviderID, forKey: .selectedProviderID)
    try container.encode(sourceLanguage, forKey: .sourceLanguage)
    try container.encode(targetLanguage, forKey: .targetLanguage)
    try container.encode(includeMetadata, forKey: .includeMetadata)
    try container.encode(showTranslation, forKey: .showTranslation)
    try container.encode(textDirection, forKey: .textDirection)
    try container.encode(bubbleShape, forKey: .bubbleShape)
  }

  nonisolated var rawValue: String {
    guard let data = RawCodableStore.encode(self), let value = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return value
  }

  private enum CodingKeys: String, CodingKey {
    case selectedProviderID
    case sourceLanguage
    case targetLanguage
    case includeMetadata
    case showTranslation
    case textDirection
    case bubbleShape
  }
}
