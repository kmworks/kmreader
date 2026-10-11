import Foundation
import GRDB

nonisolated struct MangaTranslationStore {
  static func save(_ translation: MangaPageTranslation, database: DatabaseOperator?) async throws {
    guard let database else { return }
    var record = try MangaTranslationRecord(translation)
    _ = try await database.write { db in
      try record.save(db)
    }
  }

  static func fetch(
    key: MangaTranslationPageKey,
    database: DatabaseOperator?
  ) async throws -> MangaPageTranslation? {
    guard let database else { return nil }
    let record = try await database.read { db in
      try MangaTranslationRecord
        .filter(Column("instance_id") == key.instanceId && Column("cache_key") == key.cacheKey)
        .fetchOne(db)
    }
    return try record?.translation()
  }

  static func clear(database: DatabaseOperator) async throws {
    _ = try await database.write { db in
      try MangaTranslationRecord.deleteAll(db)
    }
  }

  static func count(database: DatabaseOperator) async throws -> Int {
    try await database.read { db in
      try MangaTranslationRecord.fetchCount(db)
    }
  }
}
