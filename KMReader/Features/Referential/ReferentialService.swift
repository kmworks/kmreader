//
// ReferentialService.swift
//
//

import Foundation

nonisolated struct AuthorDTO: Codable, Sendable {
  let name: String
  let role: String?
}

nonisolated enum ReferentialService {
  private static let apiClient = APIClient.shared

  /// Fetches a metadata string list, preferring the v2 endpoint and falling back to the
  /// deprecated v1 endpoint for servers that do not expose the v2 endpoints yet.
  private static func fetchStringList(
    v2Path: String,
    v1Path: String,
    queryItems: [URLQueryItem],
    v2ExtraQueryItems: [URLQueryItem] = []
  ) async throws -> [String] {
    var v2QueryItems = queryItems
    v2QueryItems.append(URLQueryItem(name: "unpaged", value: "true"))
    v2QueryItems.append(contentsOf: v2ExtraQueryItems)

    do {
      let page: Page<String> = try await apiClient.request(path: v2Path, queryItems: v2QueryItems)
      return page.content
    } catch {
      // Older servers do not have the v2 endpoints yet; fall back to v1.
      // Drop v2-only parameters that the v1 endpoints do not understand.
      let v1QueryItems = queryItems.filter { $0.name != "include" }
      return try await apiClient.request(path: v1Path, queryItems: v1QueryItems)
    }
  }

  /// Fetches an integer metadata list as strings, preferring the v2 endpoint
  /// (Page<Integer>) and falling back to the deprecated v1 endpoint.
  private static func fetchIntListAsStrings(
    v2Path: String,
    v1Path: String,
    queryItems: [URLQueryItem]
  ) async throws -> [String] {
    var v2QueryItems = queryItems
    v2QueryItems.append(URLQueryItem(name: "unpaged", value: "true"))

    do {
      let page: Page<Int> = try await apiClient.request(path: v2Path, queryItems: v2QueryItems)
      return page.content.map { String($0) }
    } catch {
      // The v1 endpoint maps null age ratings to the literal string "None".
      let legacy: [String] = try await apiClient.request(path: v1Path, queryItems: queryItems)
      return legacy.filter { $0 != "None" }
    }
  }

  static func getNotableEntities(
    libraryIds: [String]? = nil,
    collectionId: String? = nil,
    seriesId: String? = nil,
    readListId: String? = nil
  ) async throws -> [NotableEntity] {
    var queryItems = [URLQueryItem(name: "unpaged", value: "true")]
    for id in libraryIds ?? [] where !id.isEmpty {
      queryItems.append(URLQueryItem(name: "library_id", value: id))
    }
    if let collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }
    if let seriesId {
      queryItems.append(URLQueryItem(name: "series_id", value: seriesId))
    }
    if let readListId {
      queryItems.append(URLQueryItem(name: "readlist_id", value: readListId))
    }
    let page: PageResponse<NotableEntity> = try await apiClient.request(
      path: "/api/v3/notable-entities", queryItems: queryItems)
    return page.content
  }

  static func getPublishers(libraryIds: [String]? = nil, collectionId: String? = nil) async throws
    -> [String]
  {
    var queryItems: [URLQueryItem] = []

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    return try await fetchStringList(
      v2Path: "/api/v2/publishers",
      v1Path: "/api/v1/publishers",
      queryItems: queryItems
    )
  }

  static func getGenres(libraryIds: [String]? = nil, collectionId: String? = nil) async throws
    -> [String]
  {
    var queryItems: [URLQueryItem] = []

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    return try await fetchStringList(
      v2Path: "/api/v2/genres",
      v1Path: "/api/v1/genres",
      queryItems: queryItems
    )
  }

  static func getTags(libraryIds: [String]? = nil, collectionId: String? = nil) async throws -> [String] {
    var queryItems: [URLQueryItem] = []

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    return try await fetchStringList(
      v2Path: "/api/v2/tags",
      v1Path: "/api/v1/tags",
      queryItems: queryItems,
      v2ExtraQueryItems: [URLQueryItem(name: "include", value: "BOTH")]
    )
  }

  static func getBookTags(
    seriesId: String? = nil, readListId: String? = nil, libraryIds: [String]? = nil
  ) async throws -> [String] {
    var queryItems: [URLQueryItem] = []

    if let seriesId = seriesId {
      queryItems.append(URLQueryItem(name: "series_id", value: seriesId))
    }

    if let readListId = readListId {
      queryItems.append(URLQueryItem(name: "readlist_id", value: readListId))
    }

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    return try await fetchStringList(
      v2Path: "/api/v2/tags",
      v1Path: "/api/v1/tags/book",
      queryItems: queryItems,
      v2ExtraQueryItems: [URLQueryItem(name: "include", value: "BOOK")]
    )
  }

  static func getLanguages(libraryIds: [String]? = nil, collectionId: String? = nil) async throws
    -> [String]
  {
    var queryItems: [URLQueryItem] = []

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    return try await fetchStringList(
      v2Path: "/api/v2/languages",
      v1Path: "/api/v1/languages",
      queryItems: queryItems
    )
  }

  static func getAgeRatings(libraryIds: [String]? = nil, collectionId: String? = nil) async throws
    -> [String]
  {
    var queryItems: [URLQueryItem] = []

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    return try await fetchIntListAsStrings(
      v2Path: "/api/v2/age-ratings",
      v1Path: "/api/v1/age-ratings",
      queryItems: queryItems
    )
  }

  static func getReleaseYears(libraryIds: [String]? = nil, collectionId: String? = nil) async throws
    -> [String]
  {
    var queryItems: [URLQueryItem] = []

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    return try await fetchStringList(
      v2Path: "/api/v2/series/release-years",
      v1Path: "/api/v1/series/release-dates",
      queryItems: queryItems
    )
  }
  static func getAuthorsNames(
    seriesId: String? = nil,
    libraryIds: [String]? = nil,
    collectionId: String? = nil,
    readListId: String? = nil,
    search: String? = nil
  ) async throws -> [String] {
    var queryItems: [URLQueryItem] = []

    if let seriesId = seriesId {
      queryItems.append(URLQueryItem(name: "series_id", value: seriesId))
    }

    if let libraryIds = libraryIds, !libraryIds.isEmpty {
      for id in libraryIds where !id.isEmpty {
        queryItems.append(URLQueryItem(name: "library_id", value: id))
      }
    }

    if let collectionId = collectionId {
      queryItems.append(URLQueryItem(name: "collection_id", value: collectionId))
    }

    if let readListId = readListId {
      queryItems.append(URLQueryItem(name: "readlist_id", value: readListId))
    }

    if let search = search, !search.isEmpty {
      queryItems.append(URLQueryItem(name: "search", value: search))
    }

    var v2QueryItems = queryItems
    v2QueryItems.append(URLQueryItem(name: "unpaged", value: "true"))

    do {
      let page: Page<AuthorDTO> = try await apiClient.request(
        path: "/api/v2/authors",
        queryItems: v2QueryItems
      )
      let names = page.content.map { $0.name }
      var seen = Set<String>()
      let unique = names.filter { seen.insert($0).inserted }
      return unique
    } catch {
      let v1QueryItems = queryItems.filter { $0.name != "readlist_id" }
      let authors: [AuthorDTO] = try await apiClient.request(path: "/api/v1/authors", queryItems: v1QueryItems)
      let names = authors.map { $0.name }
      var seen = Set<String>()
      let unique = names.filter { seen.insert($0).inserted }
      return unique
    }
  }
}
