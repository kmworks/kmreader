//
// ServerReadingTopsResponse.swift
//
//

import Foundation

/// `GET /api/v1/stats/reading/tops`: content composition over completed books.
nonisolated struct ServerReadingTopsResponse: Decodable, Sendable {
  let topAuthors: [ReadingStatsItem]
  let topGenres: [ReadingStatsItem]
  let topTags: [ReadingStatsItem]
  let genreDistribution: [ReadingStatsItem]
  let tagDistribution: [ReadingStatsItem]
  let generatedAt: String?

  private enum CodingKeys: String, CodingKey {
    case topAuthors
    case topGenres
    case topTags
    case genreDistribution
    case tagDistribution
    case generatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    topAuthors = try container.decodeIfPresent([ReadingStatsItem].self, forKey: .topAuthors) ?? []
    topGenres = try container.decodeIfPresent([ReadingStatsItem].self, forKey: .topGenres) ?? []
    topTags = try container.decodeIfPresent([ReadingStatsItem].self, forKey: .topTags) ?? []
    genreDistribution = try container.decodeIfPresent([ReadingStatsItem].self, forKey: .genreDistribution) ?? []
    tagDistribution = try container.decodeIfPresent([ReadingStatsItem].self, forKey: .tagDistribution) ?? []
    generatedAt = try container.decodeFirstString(forKeys: [.generatedAt])
  }
}
