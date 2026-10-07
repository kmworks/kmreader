//
// SSEEvent.swift
//
//

import Foundation

// MARK: - SSE Event Types

enum SSEEventType: String, Codable, Sendable {
  case libraryAdded = "LibraryAdded"
  case libraryChanged = "LibraryChanged"
  case libraryDeleted = "LibraryDeleted"

  case seriesAdded = "SeriesAdded"
  case seriesChanged = "SeriesChanged"
  case seriesDeleted = "SeriesDeleted"

  case bookAdded = "BookAdded"
  case bookChanged = "BookChanged"
  case bookDeleted = "BookDeleted"
  case bookImported = "BookImported"

  case collectionAdded = "CollectionAdded"
  case collectionChanged = "CollectionChanged"
  case collectionDeleted = "CollectionDeleted"

  case readListAdded = "ReadListAdded"
  case readListChanged = "ReadListChanged"
  case readListDeleted = "ReadListDeleted"

  case smartListAdded = "SmartListAdded"
  case smartListChanged = "SmartListChanged"
  case smartListDeleted = "SmartListDeleted"
  case smartListThumbnailChanged = "SmartListThumbnailChanged"

  case readProgressChanged = "ReadProgressChanged"
  case readProgressDeleted = "ReadProgressDeleted"
  case readProgressSeriesChanged = "ReadProgressSeriesChanged"
  case readProgressSeriesDeleted = "ReadProgressSeriesDeleted"

  case thumbnailBookAdded = "ThumbnailBookAdded"
  case thumbnailBookDeleted = "ThumbnailBookDeleted"
  case thumbnailSeriesAdded = "ThumbnailSeriesAdded"
  case thumbnailSeriesDeleted = "ThumbnailSeriesDeleted"
  case thumbnailReadListAdded = "ThumbnailReadListAdded"
  case thumbnailReadListDeleted = "ThumbnailReadListDeleted"
  case thumbnailCollectionAdded = "ThumbnailSeriesCollectionAdded"
  case thumbnailCollectionDeleted = "ThumbnailSeriesCollectionDeleted"

  case taskQueueStatus = "TaskQueueStatus"
  case sessionExpired = "SessionExpired"
}

// MARK: - SSE Event Data Models

struct LibrarySSEDto: Codable, Sendable {
  let libraryId: String
}

struct SeriesSSEDto: Codable, Sendable {
  let seriesId: String
  let libraryId: String
}

struct BookSSEDto: Codable, Sendable {
  let bookId: String
  let seriesId: String
  let libraryId: String
}

struct CollectionSSEDto: Codable, Sendable {
  let collectionId: String
  let seriesIds: [String]
}

struct ReadListSSEDto: Codable, Sendable {
  let readListId: String
  let bookIds: [String]
}

struct SmartListSSEDto: Codable, Sendable {
  let smartListId: String
}

struct ReadProgressSSEDto: Codable, Sendable {
  let bookId: String
  let userId: String
}

struct ReadProgressSeriesSSEDto: Codable, Sendable {
  let seriesId: String
  let userId: String
}

struct ThumbnailBookSSEDto: Codable, Sendable {
  let bookId: String
  let seriesId: String
  let selected: Bool
}

struct ThumbnailSeriesSSEDto: Codable, Sendable {
  let seriesId: String
  let selected: Bool
}

struct ThumbnailReadListSSEDto: Codable, Sendable {
  let readListId: String
  let selected: Bool
}

struct ThumbnailCollectionSSEDto: Codable, Sendable {
  let collectionId: String
  let selected: Bool
}

struct SessionExpiredSSEDto: Codable, Sendable {
  let userId: String
}

struct TaskQueueSSEDto: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  let count: Int
  let countByType: [String: Int]

  // MARK: - Initializers
  nonisolated init(count: Int = 0, countByType: [String: Int] = [:]) {
    self.count = count
    self.countByType = countByType
  }

  // MARK: - RawRepresentable
  nonisolated var rawValue: String {
    let dict: [String: Any] = [
      "count": count,
      "countByType": countByType,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    {
      return json
    }
    return "{}"
  }

  nonisolated init?(rawValue: String) {
    guard !rawValue.isEmpty else {
      self.count = 0
      self.countByType = [:]
      return
    }
    guard let data = rawValue.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      self.count = 0
      self.countByType = [:]
      return
    }
    self.count = dict["count"] as? Int ?? 0
    self.countByType = dict["countByType"] as? [String: Int] ?? [:]
  }
}

struct BookImportSSEDto: Codable, Sendable {
  let bookId: String?
  let sourceFile: String
  let success: Bool
  let message: String?
}
