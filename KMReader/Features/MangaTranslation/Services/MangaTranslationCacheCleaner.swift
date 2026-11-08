import Foundation

enum MangaTranslationCacheCleaner {
  static func clear() {
    Task {
      do {
        if let database = await DatabaseOperator.databaseIfConfigured() {
          try await MangaTranslationService.shared.clearTranslations(
            instanceId: AppConfig.current.instanceId,
            database: database
          )
        }
        ErrorManager.shared.notify(message: String(localized: "Cache cleared"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
