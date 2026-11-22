//
// SeriesSortField.swift
//
//

import Foundation

enum SeriesSortField: String, CaseIterable, Sendable {
  case name = "metadata.titleSort"
  case dateAdded = "createdDate"
  case dateUpdated = "lastModifiedDate"
  case dateRead = "readDate"
  case releaseDate = "booksMetadata.releaseDate"
  case downloadDate = "downloadAt"
  case folderName = "name"
  case booksCount = "booksCount"
  case random = "random"

  var displayName: String {
    switch self {
    case .name: return String(localized: "series.sortField.name")
    case .dateAdded: return String(localized: "series.sortField.dateAdded")
    case .dateUpdated: return String(localized: "series.sortField.dateUpdated")
    case .dateRead: return String(localized: "series.sortField.dateRead")
    case .releaseDate: return String(localized: "series.sortField.releaseDate")
    case .downloadDate: return String(localized: "series.sortField.downloadDate")
    case .folderName: return String(localized: "series.sortField.folderName")
    case .booksCount: return String(localized: "series.sortField.booksCount")
    case .random: return String(localized: "series.sortField.random")
    }
  }

  static var onlineCases: [SeriesSortField] {
    allCases.filter { $0 != .downloadDate }
  }

  static var offlineCases: [SeriesSortField] {
    Array(allCases)
  }

  var supportsDirection: Bool {
    self != .random
  }

  /// Keys persisted by earlier builds, which stored the series DTO field names
  /// instead of the sort keys `/api/v1/series/list` documents: `fileLastModified`
  /// and `metadata.title` were dropped by the server, so those orders did
  /// nothing. The raw values above replace them; saved options and presets still
  /// carry the older strings and decode through this map, which can go away once
  /// no build before this one can load.
  nonisolated static func decode(_ value: String) -> SeriesSortField? {
    if let field = SeriesSortField(rawValue: value) { return field }
    switch value {
    case "created": return .dateAdded
    case "lastModified": return .dateUpdated
    case "fileLastModified": return .dateRead
    case "metadata.title": return .folderName
    default: return nil
    }
  }
}
