//
// ServerReadingActivityResponse.swift
//
//

import Foundation

/// `GET /api/v1/stats/reading/activity`: weekday (index 0 = Sunday) and hourly
/// counts plus the sparse UTC-day time series.
nonisolated struct ServerReadingActivityResponse: Decodable, Sendable {
  let weekdayDistribution: [Int]
  let hourlyDistribution: [Int]
  let readingTimeSeries: [ReadingStatsTimePoint]
  let generatedAt: String?

  private enum CodingKeys: String, CodingKey {
    case weekdayDistribution
    case hourlyDistribution
    case readingTimeSeries
    case generatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    weekdayDistribution = try container.decodeIfPresent([Int].self, forKey: .weekdayDistribution) ?? []
    hourlyDistribution = try container.decodeIfPresent([Int].self, forKey: .hourlyDistribution) ?? []
    readingTimeSeries =
      try container.decodeIfPresent([ReadingStatsTimePoint].self, forKey: .readingTimeSeries) ?? []
    generatedAt = try container.decodeFirstString(forKeys: [.generatedAt])
  }
}
