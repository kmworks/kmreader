import Foundation

/// Lookup key for a page translation held in memory for one reading session.
/// Unlike `MangaTranslationPageKey` it carries no source/provider/model
/// signatures; the configuration stamp substitutes for them so mid-session
/// configuration changes stop matching stale results.
struct MangaTranslationSessionKey: Hashable, Sendable {
  let pageID: ReaderPageID
  let splitMode: PageSplitMode
  let rotation: ReaderRotation
  let borderCropMode: ReaderPageBorderCropMode
  let configurationStamp: String

  /// Snapshot of everything translation output depends on that is readable
  /// synchronously. Provider configuration edits live in GRDB and are covered
  /// by the settings-dismiss refresh instead.
  static func currentConfigurationStamp() -> String {
    let preferences = AppConfig.mangaTranslation
    var values: [String: String] = [
      "sourceLanguage": preferences.sourceLanguage,
      "targetLanguage": preferences.targetLanguage,
      "includeMetadata": String(preferences.includeMetadata),
      "provider": preferences.selectedProviderID,
    ]
    for (key, value) in AppConfig.modelLibrary.selectedStorageKeys {
      values["model.\(key)"] = value
    }
    return MangaSignature.make(values)
  }
}
