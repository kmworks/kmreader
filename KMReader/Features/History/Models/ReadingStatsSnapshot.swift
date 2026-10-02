//
// ReadingStatsSnapshot.swift
//
//

import Foundation

nonisolated struct ReadingStatsSnapshot: Codable, Equatable, Sendable {
  let libraryId: String
  let cachedAt: Date
  let payload: ReadingStatsPayload
  let dataSource: ReadingStatsDataSource

  init(
    libraryId: String,
    cachedAt: Date,
    payload: ReadingStatsPayload,
    dataSource: ReadingStatsDataSource = .local
  ) {
    self.libraryId = libraryId
    self.cachedAt = cachedAt
    self.payload = payload
    self.dataSource = dataSource
  }

  private enum CodingKeys: String, CodingKey {
    case libraryId
    case cachedAt
    case payload
    case dataSource
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    libraryId = try container.decode(String.self, forKey: .libraryId)
    cachedAt = try container.decode(Date.self, forKey: .cachedAt)
    payload = try container.decode(ReadingStatsPayload.self, forKey: .payload)
    // Snapshots written before the source was tracked predate server-side stats.
    dataSource = try container.decodeIfPresent(ReadingStatsDataSource.self, forKey: .dataSource) ?? .local
  }
}
