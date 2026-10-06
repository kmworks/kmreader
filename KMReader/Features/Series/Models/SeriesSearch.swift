//
// SeriesSearch.swift
//
//

import Foundation

// Simplified search structure that can encode to the correct JSON format for series list API
nonisolated struct SeriesSearch: Encodable {
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

nonisolated struct SeriesSearchFilters {
  var libraryIds: [String]? = nil
  var includeReadStatuses: [ReadStatus] = []
  var excludeReadStatuses: [ReadStatus] = []
  var includeSeriesStatuses: [String] = []
  var excludeSeriesStatuses: [String] = []
  var seriesStatusLogic: FilterLogic = .all
  /// oneshot = true / false / nil
  var oneshot: Bool? = nil
  /// deleted = true / false / nil
  var deleted: Bool? = nil
  /// complete = true / false / nil
  var complete: Bool? = nil
  var collectionId: String? = nil

  // Metadata filters
  var publishers: [String]? = nil
  var publishersLogic: FilterLogic = .all
  var authors: [String]? = nil
  var authorsLogic: FilterLogic = .all
  var genres: [String]? = nil
  var genresLogic: FilterLogic = .all
  var tags: [String]? = nil
  var tagsLogic: FilterLogic = .all
  var languages: [String]? = nil
  var languagesLogic: FilterLogic = .all
  var ageRatings: [Int]? = nil
  var ageRatingsLogic: FilterLogic = .all
  var releaseYears: [Int]? = nil
  var releaseYearsLogic: FilterLogic = .all
}

// Helper functions to build conditions
extension SeriesSearch {
  nonisolated static func buildCondition(filters: SeriesSearchFilters) -> [String: Any]? {
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
        ["readStatus": ["operator": "isNot", "value": $0.rawValue]]
      }
      conditions.append(["allOf": statusConditions])
    }

    if !filters.includeSeriesStatuses.isEmpty {
      let statusConditions = filters.includeSeriesStatuses.map { status in
        ["seriesStatus": ["operator": "is", "value": status]]
      }
      let wrapperKey = filters.seriesStatusLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: statusConditions])
    }

    if !filters.excludeSeriesStatuses.isEmpty {
      let statusConditions = filters.excludeSeriesStatuses.map { status in
        ["seriesStatus": ["operator": "isNot", "value": status]]
      }
      let wrapperKey = filters.seriesStatusLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: statusConditions])
    }

    if let oneshot = filters.oneshot {
      conditions.append([
        "oneShot": [
          "operator": oneshot ? "isTrue" : "isFalse"
        ]
      ])
    }

    if let complete = filters.complete {
      conditions.append([
        "complete": [
          "operator": complete ? "isTrue" : "isFalse"
        ]
      ])
    }

    if let deleted = filters.deleted {
      conditions.append([
        "deleted": [
          "operator": deleted ? "isTrue" : "isFalse"
        ]
      ])
    }

    if let collectionId = filters.collectionId {
      conditions.append([
        "collectionId": ["operator": "is", "value": collectionId]
      ])
    }

    // Metadata filters
    if let publishers = filters.publishers, !publishers.isEmpty {
      let publisherConditions = publishers.map { publisher in
        ["publisher": ["operator": "is", "value": publisher]]
      }
      let wrapperKey = filters.publishersLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: publisherConditions])
    }

    if let authors = filters.authors, !authors.isEmpty {
      let authorConditions = authors.map { author in
        ["author": ["operator": "is", "value": ["name": author]]]
      }
      let wrapperKey = filters.authorsLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: authorConditions])
    }

    if let genres = filters.genres, !genres.isEmpty {
      let genreConditions = genres.map { genre in
        ["genre": ["operator": "is", "value": genre]]
      }
      let wrapperKey = filters.genresLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: genreConditions])
    }

    if let tags = filters.tags, !tags.isEmpty {
      let tagConditions = tags.map { tag in
        ["tag": ["operator": "is", "value": tag]]
      }
      let wrapperKey = filters.tagsLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: tagConditions])
    }

    if let languages = filters.languages, !languages.isEmpty {
      let languageConditions = languages.map { language in
        ["language": ["operator": "is", "value": language]]
      }
      let wrapperKey = filters.languagesLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: languageConditions])
    }

    if let ageRatings = filters.ageRatings, !ageRatings.isEmpty {
      let ageRatingConditions = ageRatings.map { rating in
        ["ageRating": ["operator": "is", "value": rating]]
      }
      let wrapperKey = filters.ageRatingsLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: ageRatingConditions])
    }

    if let releaseYears = filters.releaseYears, !releaseYears.isEmpty {
      let releaseYearConditions = releaseYears.map { year in
        [
          "allOf": [
            ["releaseDate": ["operator": "after", "dateTime": "\(year - 1)-12-31T12:00:00Z"]],
            ["releaseDate": ["operator": "before", "dateTime": "\(year + 1)-01-01T12:00:00Z"]],
          ]
        ]
      }
      let wrapperKey = filters.releaseYearsLogic == .all ? "allOf" : "anyOf"
      conditions.append([wrapperKey: releaseYearConditions])
    }

    if conditions.isEmpty {
      return nil
    } else if conditions.count == 1 {
      return conditions[0]
    } else {
      return ["allOf": conditions]
    }
  }
}
