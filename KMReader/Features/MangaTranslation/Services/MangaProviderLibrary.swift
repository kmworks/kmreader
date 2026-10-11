import Foundation
import GRDB

nonisolated enum MangaProviderLibrary {
  static func current(database: DatabaseOperator?) async throws -> MangaProviderConfig? {
    let selectedID = AppConfig.mangaTranslation.selectedProviderID
    guard let database, !selectedID.isEmpty else { return nil }
    return try await database.read { db in
      try MangaProviderConfig.filter(Column("id") == selectedID).fetchOne(db)
    }
  }

  static func all(database: DatabaseOperator?) async throws -> [MangaProviderConfig] {
    guard let database else { return [] }
    let providers = try await database.read { db in
      try MangaProviderConfig.fetchAll(db)
    }
    return providers.sorted {
      $0.resolvedDisplayName.localizedStandardCompare($1.resolvedDisplayName) == .orderedAscending
    }
  }

  static func save(
    _ provider: MangaProviderConfig,
    select: Bool = false,
    database: DatabaseOperator
  ) async throws {
    guard !provider.id.isEmpty else { return }
    var normalized = provider
    normalized.baseURL = MangaProviderConfig.normalizedBaseURL(provider.baseURL)
    normalized.model = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
    normalized.displayName = provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    normalized.apiKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try await database.write { db in
      try normalized.save(db)
    }
    if select {
      var preferences = AppConfig.mangaTranslation
      preferences.selectedProviderID = provider.id
      AppConfig.mangaTranslation = preferences
    }
  }

  static func delete(_ provider: MangaProviderConfig, database: DatabaseOperator) async throws {
    _ = try await database.write { db in
      try provider.delete(db)
    }
    if AppConfig.mangaTranslation.selectedProviderID == provider.id {
      var preferences = AppConfig.mangaTranslation
      preferences.selectedProviderID = ""
      AppConfig.mangaTranslation = preferences
    }
  }
}
