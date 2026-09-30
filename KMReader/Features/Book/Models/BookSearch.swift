//
// BookSearch.swift
//
//

import Foundation

// Simplified search structure that can encode to the correct JSON format
nonisolated struct BookSearch: Encodable {
  let condition: [String: Any]?
  let fullTextSearch: String?

  init(condition: [String: Any]? = nil, fullTextSearch: String? = nil) {
    self.condition = condition
    self.fullTextSearch = fullTextSearch
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    if let condition = condition {
      // Use JSONSerialization to encode the condition dictionary
      let conditionJSON = try JSONSerialization.data(
        withJSONObject: condition, options: [.sortedKeys])
      // Decode it back to a proper Codable structure
      let conditionDict = try JSONDecoder().decode([String: JSONAny].self, from: conditionJSON)
      try container.encodeIfPresent(conditionDict, forKey: .condition)
    }

    try container.encodeIfPresent(fullTextSearch, forKey: .fullTextSearch)
  }

  private enum CodingKeys: String, CodingKey {
    case condition
    case fullTextSearch
  }
}

nonisolated struct BookSearchFilters {
  var libraryIds: [String]? = nil
  var includeReadStatuses: [ReadStatus] = []
  var excludeReadStatuses: [ReadStatus] = []
  /// oneshot = true / false / nil
  var oneshot: Bool? = nil
  /// deleted = true / false / nil
  var deleted: Bool? = nil
  var seriesId: String? = nil
  var readListId: String? = nil
  var releaseDateAfter: Date? = nil

  // Metadata filters
  var authors: [String]? = nil
  var authorsLogic: FilterLogic = .all
  var tags: [String]? = nil
  var tagsLogic: FilterLogic = .all
}

// Helper functions to build conditions
extension BookSearch {
  nonisolated static func buildCondition(filters: BookSearchFilters) -> [String: Any]? {
    var conditions: [[String: Any]] = []

    // Support multiple libraryIds using anyOf
    if let libraryIds = filters.libraryIds, !libraryIds.isEmpty {
      if libraryIds.count == 1 {
        // Single libraryId - use simple condition
        conditions.append([
          "libraryId": ["operator": "is", "value": libraryIds[0]]
        ])
      } else {
        // Multiple libraryIds - use anyOf to combine
        let libraryConditions = libraryIds.map { id in
          ["libraryId": ["operator": "is", "value": id]]
        }
        conditions.append(["anyOf": libraryConditions])
      }
    }

    if !filters.includeReadStatuses.isEmpty {
      let statusConditions = filters.includeReadStatuses.map {
        ["readStatus": ["operator": "is", "value": $0.rawValue]]
      }
      conditions.append(["anyOf": statusConditions])
    }

    if !filters.excludeReadStatuses.isEmpty {
      let statusConditions = filters.excludeReadStatuses.map {
        ["readStatus": ["operator": "isnot", "value": $0.rawValue]]
      }
      conditions.append(["allOf": statusConditions])
    }

    if let seriesId = filters.seriesId {
      conditions.append([
        "seriesId": ["operator": "is", "value": seriesId]
      ])
    }

    if let readListId = filters.readListId {
      conditions.append([
        "readListId": ["operator": "is", "value": readListId]
      ])
    }

    if let releaseDateAfter = filters.releaseDateAfter {
      conditions.append([
        "releaseDate": [
          "operator": "after",
          "dateTime": iso8601UTCString(from: releaseDateAfter),
        ]
      ])
    }

    if let oneshot = filters.oneshot {
      conditions.append([
        "oneshot": [
          "operator": oneshot ? "istrue" : "isfalse"
        ]
      ])
    }

    if let deleted = filters.deleted {
      conditions.append([
        "deleted": [
          "operator": deleted ? "istrue" : "isfalse"
        ]
      ])
    }

    // Metadata filters
    if let authors = filters.authors, !authors.isEmpty {
      let authorConditions = authors.map { author in
        ["author": ["operator": "is", "value": ["name": author]]]
      }
      let wrapperKey = filters.authorsLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: authorConditions])
    }

    if let tags = filters.tags, !tags.isEmpty {
      let tagConditions = tags.map { tag in
        ["tag": ["operator": "is", "value": tag]]
      }
      let wrapperKey = filters.tagsLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: tagConditions])
    }

    if conditions.isEmpty {
      return nil
    } else if conditions.count == 1 {
      return conditions[0]
    } else {
      return ["allOf": conditions]
    }
  }

  private nonisolated static func iso8601UTCString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
