//
// KomfService.swift
//
//

import Foundation

/// kmrs-private komf proxy endpoints (admin only, absent on Komga servers).
nonisolated enum KomfService {
  private static let apiClient = APIClient.shared

  static func getIntegration() async throws -> KomfIntegration {
    try await apiClient.request(path: "/api/v1/komf/integration")
  }

  static func search(name: String, libraryId: String, seriesId: String) async throws
    -> [KomfSearchResult]
  {
    try await apiClient.request(
      path: "/api/v1/komf/search",
      queryItems: [
        URLQueryItem(name: "name", value: name),
        URLQueryItem(name: "libraryId", value: libraryId),
        URLQueryItem(name: "seriesId", value: seriesId),
      ]
    )
  }

  static func identify(
    libraryId: String,
    seriesId: String,
    provider: String,
    providerSeriesId: String
  ) async throws -> KomfMetadataJobResponse {
    let payload = KomfIdentifyRequest(
      libraryId: libraryId,
      seriesId: seriesId,
      provider: provider,
      providerSeriesId: providerSeriesId
    )
    let body = try JSONSerialization.data(
      withJSONObject: payload.jsonObject, options: [.sortedKeys])
    return try await apiClient.request(
      path: "/api/v1/komf/identify",
      method: "POST",
      body: body
    )
  }

  static func matchSeries(libraryId: String, seriesId: String) async throws
    -> KomfMetadataJobResponse
  {
    try await apiClient.request(
      path: "/api/v1/komf/match/library/\(libraryId)/series/\(seriesId)",
      method: "POST"
    )
  }

  static func resetSeries(libraryId: String, seriesId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/komf/reset/library/\(libraryId)/series/\(seriesId)",
      method: "POST"
    )
  }

  static func getJob(id: String) async throws -> KomfJob {
    try await apiClient.request(path: "/api/v1/komf/jobs/\(id)")
  }
}
