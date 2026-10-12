import Foundation
import GRDB

nonisolated struct MangaTranslationRecord: FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "manga_translations"

  let instanceId: String
  let cacheKey: String
  let resultRaw: Data
  let createdAt: Date

  init(_ translation: MangaPageTranslation) throws {
    instanceId = translation.key.instanceId
    cacheKey = translation.key.cacheKey
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    resultRaw = try encoder.encode(translation)
    createdAt = translation.createdAt
  }

  init(row: Row) throws {
    instanceId = row["instance_id"]
    cacheKey = row["cache_key"]
    resultRaw = row["result_raw"]
    createdAt = row["created_at"]
  }

  func translation() throws -> MangaPageTranslation {
    try JSONDecoder().decode(MangaPageTranslation.self, from: resultRaw)
  }

  func encode(to container: inout PersistenceContainer) throws {
    container[Column("instance_id")] = instanceId
    container[Column("cache_key")] = cacheKey
    container[Column("result_raw")] = resultRaw
    container[Column("created_at")] = createdAt
  }

  enum CodingKeys: String, CodingKey {
    case instanceId = "instance_id"
    case cacheKey = "cache_key"
    case resultRaw = "result_raw"
    case createdAt = "created_at"
  }
}
