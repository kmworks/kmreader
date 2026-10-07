//
// SeriesService.swift
//
//

import Foundation

nonisolated enum SeriesService {
  private static let apiClient = APIClient.shared

  static func getSeries(
    libraryIds: [String]? = nil,
    page: Int = 0,
    size: Int = 20,
    browseOpts: SeriesBrowseOptions,
    searchTerm: String? = nil
  ) async throws -> Page<Series> {
    let sort = searchTerm?.isEmpty == false ? nil : browseOpts.sortString
    var filters = browseOpts.toSearchFilters()
    filters.libraryIds = libraryIds
    let condition = SeriesSearch.buildCondition(filters: filters)

    let search = SeriesSearch(
      condition: condition,
      fullTextSearch: searchTerm?.isEmpty == false ? searchTerm : nil
    )

    return try await getSeriesList(
      search: search,
      page: page,
      size: size,
      sort: sort
    )
  }

  static func getSeriesList(
    search: SeriesSearch,
    page: Int = 0,
    size: Int = 20,
    sort: String? = nil,
    unpaged: Bool = false
  ) async throws -> Page<Series> {
    var queryItems: [URLQueryItem] = []

    if unpaged {
      queryItems.append(URLQueryItem(name: "unpaged", value: "true"))
    } else {
      queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
      queryItems.append(URLQueryItem(name: "size", value: "\(size)"))
    }

    if let sort = sort {
      queryItems.append(URLQueryItem(name: "sort", value: sort))
    }

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(search)

    return try await apiClient.request(
      path: "/api/v1/series/list",
      method: "POST",
      body: jsonData,
      queryItems: queryItems
    )
  }

  static func getOneSeries(id: String) async throws -> Series {
    return try await apiClient.request(path: "/api/v1/series/\(id)")
  }

  static func getSeriesCollections(seriesId: String) async throws -> [SeriesCollection] {
    return try await apiClient.request(path: "/api/v1/series/\(seriesId)/collections")
  }

  static func getNewSeries(
    libraryIds: [String]? = nil,
    page: Int = 0,
    size: Int = 20
  ) async throws -> Page<Series> {
    var queryItems = [
      URLQueryItem(name: "page", value: "\(page)"),
      URLQueryItem(name: "size", value: "\(size)"),
      URLQueryItem(name: "oneshot", value: "false"),
    ]

    // Support multiple libraryIds
    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    return try await apiClient.request(path: "/api/v1/series/new", queryItems: queryItems)
  }

  static func getUpdatedSeries(
    libraryIds: [String]? = nil,
    page: Int = 0,
    size: Int = 20
  ) async throws -> Page<Series> {
    var queryItems = [
      URLQueryItem(name: "page", value: "\(page)"),
      URLQueryItem(name: "size", value: "\(size)"),
      URLQueryItem(name: "oneshot", value: "false"),
    ]

    // Support multiple libraryIds
    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    return try await apiClient.request(path: "/api/v1/series/updated", queryItems: queryItems)
  }

  /// Get thumbnail URL for a series
  static func getSeriesThumbnailURL(id: String) -> URL? {
    let baseURL = AppConfig.current.serverURL
    guard !baseURL.isEmpty else { return nil }
    return URL(string: baseURL + "/api/v1/series/\(id)/thumbnail")
  }

  static func markAsRead(seriesId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/series/\(seriesId)/read-progress",
      method: "POST"
    )
  }

  static func markAsUnread(seriesId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/series/\(seriesId)/read-progress",
      method: "DELETE"
    )
  }

  static func analyzeSeries(seriesId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/series/\(seriesId)/analyze",
      method: "POST"
    )
  }

  static func refreshMetadata(seriesId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/series/\(seriesId)/metadata/refresh",
      method: "POST"
    )
  }

  static func deleteSeries(seriesId: String) async throws {
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/series/\(seriesId)/file",
      method: "DELETE"
    )
  }

  static func updateSeriesMetadata(seriesId: String, metadata: [String: Any]) async throws {
    let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/series/\(seriesId)/metadata",
      method: "PATCH",
      body: jsonData
    )
  }
}
