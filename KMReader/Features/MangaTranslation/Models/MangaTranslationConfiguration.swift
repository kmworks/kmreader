import Foundation

struct MangaTranslationConfiguration: Hashable, Sendable {
  let archive: ModelArchive
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
        "metadata": metadata?.signature ?? "",
      ])
    }
    return provider.signature(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      metadata: metadata
    )
  }

  nonisolated var modelSignature: String { "\(archive.sha256):inference-3" }

  nonisolated static func current(
    metadata: MangaTranslationMetadata? = nil,
    database: DatabaseOperator?
  ) async throws -> MangaTranslationConfiguration? {
    guard let archive = MangaModelLibrary.selectedArchive else { return nil }
    let preferences = AppConfig.mangaTranslation
    let sourceLanguage =
      MangaTranslationLanguage.normalized(metadata?.sourceLanguage)
      ?? preferences.sourceLanguage
    let targetLanguage =
      MangaTranslationLanguage.normalized(preferences.targetLanguage)
      ?? MangaTranslationLanguage.systemTarget
    return MangaTranslationConfiguration(
      archive: archive,
      provider: try await MangaProviderLibrary.current(database: database),
      isOffline: AppConfig.isOffline,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      metadata: preferences.includeMetadata ? metadata : nil
    )
  }
}
