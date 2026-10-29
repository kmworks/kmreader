//
// TrackerService.swift
//

import Foundation

nonisolated enum TrackerService {
  private static let apiClient = APIClient.shared

  static func getPreferences() async throws -> TrackerPreferences {
    try await apiClient.request(path: "/api/v1/trackers/preferences")
  }

  static func updatePreferences(_ preferences: TrackerPreferences) async throws -> TrackerPreferences {
    try await apiClient.request(
      path: "/api/v1/trackers/preferences",
      method: "PUT",
      body: JSONEncoder().encode(preferences)
    )
  }

  static func getAccount(provider: TrackerProvider) async throws -> TrackerAccount {
    try await apiClient.request(path: "/api/v1/trackers/oauth/\(provider.rawValue)/status")
  }

  static func logout(provider: TrackerProvider) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/trackers/oauth/\(provider.rawValue)/logout",
      method: "POST"
    )
  }

  static func getLinks(page: Int = 0, size: Int = 20, provider: TrackerProvider? = nil) async throws
    -> TrackerLinkPage
  {
    var queryItems = [
      URLQueryItem(name: "page", value: "\(page)"),
      URLQueryItem(name: "size", value: "\(size)"),
    ]
    if let provider {
      queryItems.append(URLQueryItem(name: "provider", value: provider.rawValue))
    }
    return try await apiClient.request(path: "/api/v1/trackers/links", queryItems: queryItems)
  }

  static func getLinks(seriesId: String) async throws -> [TrackerLink] {
    try await apiClient.request(path: "/api/v1/trackers/links/\(seriesId)")
  }

  static func upsertLink(
    seriesId: String,
    provider: TrackerProvider,
    trackId: String,
    title: String?,
    mode: TrackerMode,
    chapterOffset: Int
  ) async throws -> TrackerLink {
    let body = try JSONSerialization.data(
      withJSONObject: [
        "provider": provider.rawValue,
        "trackId": trackId,
        "title": title as Any,
        "trackMode": mode.rawValue,
        "chapterOffset": chapterOffset,
      ],
      options: [.sortedKeys]
    )
    return try await apiClient.request(
      path: "/api/v1/trackers/links/\(seriesId)",
      method: "PUT",
      body: body
    )
  }

  static func deleteLink(seriesId: String, provider: TrackerProvider) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/trackers/links/\(seriesId)/\(provider.rawValue)",
      method: "DELETE"
    )
  }

  static func search(provider: TrackerProvider, name: String, includeNsfw: Bool = true) async throws
    -> [TrackerSearchItem]
  {
    try await apiClient.request(
      path: "/api/v1/trackers/\(provider.rawValue)/search",
      queryItems: [
        URLQueryItem(name: "name", value: name),
        URLQueryItem(name: "nsfw", value: includeNsfw ? "true" : "false"),
      ]
    )
  }

  static func getState(provider: TrackerProvider, trackId: String) async throws -> TrackerRemoteState {
    try await apiClient.request(
      path: "/api/v1/trackers/\(provider.rawValue)/state",
      queryItems: [URLQueryItem(name: "trackId", value: trackId)]
    )
  }

  static func updateState(
    provider: TrackerProvider,
    trackId: String,
    state: [String: Any]
  ) async throws {
    var body = state
    body["trackId"] = trackId
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/trackers/\(provider.rawValue)/update",
      method: "POST",
      body: JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    )
  }

  static func getLedger(page: Int = 0, size: Int = 20) async throws -> Page<TrackerLedgerItem> {
    try await apiClient.request(
      path: "/api/v1/trackers/ledger",
      queryItems: [
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "size", value: "\(size)"),
      ]
    )
  }
}
