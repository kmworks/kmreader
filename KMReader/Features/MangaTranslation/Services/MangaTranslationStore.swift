import Foundation
import GRDB

nonisolated struct MangaTranslationStore {
  static func save(_ translation: MangaPageTranslation, database: DatabaseOperator?) async throws {
    guard let database else { return }
    var record = try MangaTranslationRecord(translation)
    let archivePrefix = translation.key.modelSignature.split(separator: ":").first.map(String.init) ?? ""
    _ = try await database.write { db in
      try record.save(db)
      // Retired inference versions can never match again; prune them for
      // this page. Rows from other model archives and same-signature
      // language/provider/geometry variants stay.
      try MangaTranslationRecord
        .filter(Column("instance_id") == record.instanceId)
        .filter(Column("book_id") == record.bookId)
        .filter(Column("page_number") == record.pageNumber)
        .filter(
          Column("model_signature") == ""
            || (Column("model_signature").like("\(archivePrefix):%")
              && Column("model_signature") != record.modelSignature)
        )
        .deleteAll(db)
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

  static func clear(instanceId: String, database: DatabaseOperator) async throws {
    _ = try await database.write { db in
      try MangaTranslationRecord
        .filter(Column("instance_id") == instanceId)
        .deleteAll(db)
    }
  }
}
