//
// ServerReadingSummaryResponse.swift
//
//

import Foundation

/// `GET /api/v1/stats/reading/summary`: the summary fields sit at the top level
/// alongside statusDistribution, so the summary decodes from the same container.
nonisolated struct ServerReadingSummaryResponse: Decodable, Sendable {
  let summary: ReadingStatsSummary
  let statusDistribution: [ReadingStatsItem]
  let generatedAt: String?

  private enum CodingKeys: String, CodingKey {
    case statusDistribution
    case generatedAt
  }

  init(from decoder: Decoder) throws {
    summary = try ReadingStatsSummary(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    statusDistribution =
      try container.decodeIfPresent([ReadingStatsItem].self, forKey: .statusDistribution) ?? []
    generatedAt = try container.decodeFirstString(forKeys: [.generatedAt])
  }
}
