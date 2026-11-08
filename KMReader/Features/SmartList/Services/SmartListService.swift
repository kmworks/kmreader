//
// SmartListService.swift
//
//

import Foundation

/// The kmrs-private smart-list endpoints (`/api/v1/smart-lists`), present
/// where the server profile lists `smartLists`.
nonisolated enum SmartListService {
  private static let apiClient = APIClient.shared

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

  static func isSupported(instanceId: String) -> Bool {
    ServerProfileService.supports(.smartLists, instanceId: instanceId)
  }
}
