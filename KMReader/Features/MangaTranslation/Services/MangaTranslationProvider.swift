import Foundation

protocol MangaTranslationProvider: Sendable {
  func translate(
    segments: [MangaTextSegment],
    sourceLanguage: String,
    targetLanguage: String,
    metadata: MangaTranslationMetadata?,
    configuration: MangaProviderConfig
  ) async throws -> [String]
}
