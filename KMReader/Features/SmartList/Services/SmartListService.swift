//
// SmartListService.swift
//
//

import Foundation

/// The kmrs-private smart-list endpoints (`/api/v1/smart-lists`). Komga
/// servers 404; the first failure is recorded per instance so later loads
/// skip the doomed request.
nonisolated enum SmartListService {
  private static let apiClient = APIClient.shared

  // An unsupported verdict expires after this interval so a server upgrade is picked up.
  private static let capabilityRecheckInterval: TimeInterval = 24 * 60 * 60

  static func getSmartLists(
    page: Int = 0,
    size: Int = 20,
    unpaged: Bool = false
  ) async throws -> Page<SmartList> {
    var queryItems: [URLQueryItem] = []

    if unpaged {
      queryItems.append(URLQueryItem(name: "unpaged", value: "true"))
    } else {
      queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
      queryItems.append(URLQueryItem(name: "size", value: "\(size)"))
    }

    return try await apiClient.request(path: "/api/v1/smart-lists", queryItems: queryItems)
  }

  static func getSmartList(id: String) async throws -> SmartList {
    return try await apiClient.request(path: "/api/v1/smart-lists/\(id)")
  }

  static func getShareTargets() async throws -> [SmartListShareTarget] {
    return try await apiClient.request(path: "/api/v1/smart-lists/share-targets")
  }

  static func createSmartList(
    name: String,
    summary: String,
    target: SmartList.Target,
    visibility: SmartList.Visibility?,
    sharedWithUserIds: [String]?,
    search: [String: Any]
  ) async throws -> SmartList {
    var body: [String: Any] = [
      "name": name,
      "summary": summary,
      "target": target.rawValue,
      "search": search,
    ]
    // Admin-only fields stay absent for non-admins; the server 403s otherwise.
    if let visibility {
      body["visibility"] = visibility.rawValue
    }
    if let sharedWithUserIds {
      body["sharedWithUserIds"] = sharedWithUserIds
    }
    let jsonData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let result: SmartList = try await apiClient.request(
      path: "/api/v1/smart-lists",
      method: "POST",
      body: jsonData
    )
    await ContentProjectionNotifier.postSmartListsDidChange(
      smartListId: result.id, refreshDelay: 0)
    return result
  }

  static func updateSmartList(
    smartListId: String,
    name: String,
    summary: String,
    visibility: SmartList.Visibility?,
    sharedWithUserIds: [String]?,
    search: [String: Any]?
  ) async throws {
    var body: [String: Any] = [
      "name": name,
      "summary": summary,
    ]
    if let visibility {
      body["visibility"] = visibility.rawValue
    }
    if let sharedWithUserIds {
      body["sharedWithUserIds"] = sharedWithUserIds
    }
    // A nil search means the editor never touched the filters; omitting it keeps
    // the stored document, which protects filters the editor cannot represent.
    if let search {
      body["search"] = search
    }
    let jsonData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/smart-lists/\(smartListId)",
      method: "PATCH",
      body: jsonData
    )
    await ContentProjectionNotifier.postSmartListsDidChange(
      smartListId: smartListId, refreshDelay: 0)
  }

  static func getSmartListBooks(
    smartListId: String,
    search: BookSearch,
    page: Int = 0,
    size: Int = 20,
    sort: [String]? = nil
  ) async throws -> Page<Book> {
    var queryItems = [
      URLQueryItem(name: "page", value: "\(page)"),
      URLQueryItem(name: "size", value: "\(size)"),
    ]

    for value in sort ?? [] {
      queryItems.append(URLQueryItem(name: "sort", value: value))
    }

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(search)

    return try await apiClient.request(
      path: "/api/v1/smart-lists/\(smartListId)/books",
      method: "POST",
      body: jsonData,
      queryItems: queryItems
    )
  }

  static func getSmartListSeries(
    smartListId: String,
    search: SeriesSearch,
    page: Int = 0,
    size: Int = 20,
    sort: [String]? = nil
  ) async throws -> Page<Series> {
    var queryItems = [
      URLQueryItem(name: "page", value: "\(page)"),
      URLQueryItem(name: "size", value: "\(size)"),
    ]

    for value in sort ?? [] {
      queryItems.append(URLQueryItem(name: "sort", value: value))
    }

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(search)

    return try await apiClient.request(
      path: "/api/v1/smart-lists/\(smartListId)/series",
      method: "POST",
      body: jsonData,
      queryItems: queryItems
    )
  }

  static func deleteSmartList(smartListId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/smart-lists/\(smartListId)",
      method: "DELETE"
    )
    await ContentProjectionNotifier.postSmartListsDidChange(
      smartListId: smartListId, refreshDelay: 0)
  }

  static func isMarkedUnsupported(instanceId: String) -> Bool {
    guard let record = AppConfig.serverSmartListCapability.record(instanceId: instanceId),
      !record.supported
    else { return false }
    return Date().timeIntervalSince(record.checkedAt) < capabilityRecheckInterval
  }

  static func recordCapability(instanceId: String, supported: Bool) {
    var capability = AppConfig.serverSmartListCapability
    // A repeated supported verdict is not worth a UserDefaults round-trip; an
    // unsupported verdict must always refresh checkedAt, it throttles re-probes.
    guard !(supported && capability.record(instanceId: instanceId)?.supported == true) else { return }
    capability.upsert(instanceId: instanceId, supported: supported, checkedAt: Date())
    AppConfig.serverSmartListCapability = capability
  }
}
