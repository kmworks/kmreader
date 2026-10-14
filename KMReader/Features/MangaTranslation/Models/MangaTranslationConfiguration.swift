import Foundation

struct MangaTranslationConfiguration: Hashable, Sendable {
  private nonisolated static let inferenceCacheVersion = "inference-6"

  let detectorArchive: ModelArchive
  let recognizerArchive: ModelArchive
  let provider: MangaProviderConfig?
  let isOffline: Bool
  let sourceLanguage: String
  let targetLanguage: String
  let metadata: MangaTranslationMetadata?

  nonisolated var hasConfiguredProvider: Bool {
    provider?.isConfigured == true
  }

  nonisolated var usesSystemProvider: Bool {
    !hasConfiguredProvider && SystemTranslationProvider.isAvailable
  }

  nonisolated var canTranslate: Bool {
    (hasConfiguredProvider && !isOffline) || usesSystemProvider
  }

  nonisolated var providerSignature: String {
    guard let provider, hasConfiguredProvider else {
      return MangaSignature.make([
        "provider": usesSystemProvider ? "system" : "unconfigured",
        "sourceLanguage": sourceLanguage,
        "targetLanguage": targetLanguage,
      ])
    }
    return provider.signature(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      metadata: metadata
    )
  }

  nonisolated var modelSignature: String {
    "\(detectorArchive.sha256):\(recognizerArchive.sha256):\(Self.inferenceCacheVersion)"
  }

  nonisolated static func current(
    metadata: MangaTranslationMetadata? = nil,
    database: DatabaseOperator?
  ) async throws -> MangaTranslationConfiguration? {
    guard let detectorArchive = MangaModelLibrary.selectedArchive(for: .detector),
      let recognizerArchive = MangaModelLibrary.selectedArchive(for: .recognizer)
    else { return nil }
    let preferences = AppConfig.mangaTranslation
    let languages = resolvedLanguages(metadata: metadata, preferences: preferences)
    return MangaTranslationConfiguration(
      detectorArchive: detectorArchive,
      recognizerArchive: recognizerArchive,
      provider: try await MangaProviderLibrary.current(database: database),
      isOffline: AppConfig.isOffline,
      sourceLanguage: languages.sourceLanguage,
      targetLanguage: languages.targetLanguage,
      metadata: preferences.includeMetadata ? metadata : nil
    )
  }

  nonisolated static func resolvedLanguages(
    metadata: MangaTranslationMetadata?,
    preferences: MangaTranslationPreferences
  ) -> (sourceLanguage: String, targetLanguage: String) {
    let sourceLanguage =
      MangaTranslationLanguage.normalized(metadata?.sourceLanguage)
      ?? MangaTranslationLanguage.normalized(preferences.sourceLanguage)
      ?? MangaTranslationLanguage.defaultSource
    let targetLanguage =
      MangaTranslationLanguage.normalized(preferences.targetLanguage)
      ?? MangaTranslationLanguage.systemTarget
    return (sourceLanguage, targetLanguage)
  }
}
