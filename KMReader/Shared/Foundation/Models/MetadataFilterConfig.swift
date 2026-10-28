//
// MetadataFilterConfig.swift
//
//

import Foundation

/// Configuration for metadata-based filtering
nonisolated struct MetadataFilterConfig: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var publishers: [String]?
  var publishersLogic: FilterLogic = .all
  var authors: [String]?
  var authorsLogic: FilterLogic = .all
  var genres: [String]?
  var genresLogic: FilterLogic = .all
  var tags: [String]?
  var tagsLogic: FilterLogic = .all
  var notableEntities: [NotableEntity]?
  var notableEntitiesLogic: FilterLogic = .all
  var languages: [String]?
  var languagesLogic: FilterLogic = .all
  var ageRatings: [String]?
  var ageRatingsLogic: FilterLogic = .all
  var releaseYears: [String]?
  var releaseYearsLogic: FilterLogic = .all

  init(
    publishers: [String]? = nil,
    publishersLogic: FilterLogic = .all,
    authors: [String]? = nil,
    authorsLogic: FilterLogic = .all,
    genres: [String]? = nil,
    genresLogic: FilterLogic = .all,
    tags: [String]? = nil,
    tagsLogic: FilterLogic = .all,
    notableEntities: [NotableEntity]? = nil,
    notableEntitiesLogic: FilterLogic = .all,
    languages: [String]? = nil,
    languagesLogic: FilterLogic = .all,
    ageRatings: [String]? = nil,
    ageRatingsLogic: FilterLogic = .all,
    releaseYears: [String]? = nil,
    releaseYearsLogic: FilterLogic = .all
  ) {
    self.publishers = publishers
    self.publishersLogic = publishersLogic
    self.authors = authors
    self.authorsLogic = authorsLogic
    self.genres = genres
    self.genresLogic = genresLogic
    self.tags = tags
    self.tagsLogic = tagsLogic
    self.notableEntities = notableEntities
    self.notableEntitiesLogic = notableEntitiesLogic
    self.languages = languages
    self.languagesLogic = languagesLogic
    self.ageRatings = ageRatings
    self.ageRatingsLogic = ageRatingsLogic
    self.releaseYears = releaseYears
    self.releaseYearsLogic = releaseYearsLogic
  }

  /// Check if any filter is active
  var hasAnyFilter: Bool {
    return publishers != nil || authors != nil || genres != nil || tags != nil
      || notableEntities != nil || languages != nil
      || ageRatings != nil || releaseYears != nil
  }

  var rawValue: String {
    var dict: [String: Any] = [:]
    if let publishers = publishers {
      dict["publishers"] = publishers
    }
    dict["publishersLogic"] = publishersLogic.rawValue
    if let authors = authors {
      dict["authors"] = authors
    }
    dict["authorsLogic"] = authorsLogic.rawValue
    if let genres = genres {
      dict["genres"] = genres
    }
    dict["genresLogic"] = genresLogic.rawValue
    if let tags = tags {
      dict["tags"] = tags
    }
    dict["tagsLogic"] = tagsLogic.rawValue
    if let notableEntities {
      dict["notableEntities"] = notableEntities.map(\.filterKey)
    }
    dict["notableEntitiesLogic"] = notableEntitiesLogic.rawValue
    if let languages = languages {
      dict["languages"] = languages
    }
    dict["languagesLogic"] = languagesLogic.rawValue
    if let ageRatings = ageRatings {
      dict["ageRatings"] = ageRatings
    }
    dict["ageRatingsLogic"] = ageRatingsLogic.rawValue
    if let releaseYears = releaseYears {
      dict["releaseYears"] = releaseYears
    }
    dict["releaseYearsLogic"] = releaseYearsLogic.rawValue
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    {
      return json
    }
    return "{}"
  }

  init?(rawValue: String) {
    guard !rawValue.isEmpty else {
      return nil
    }
    guard let data = rawValue.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    self.publishers = dict["publishers"] as? [String]
    if let publishersLogicRaw = dict["publishersLogic"] as? String,
      let logic = FilterLogic(rawValue: publishersLogicRaw)
    {
      self.publishersLogic = logic
    } else {
      self.publishersLogic = .all
    }
    self.authors = dict["authors"] as? [String]
    if let authorsLogicRaw = dict["authorsLogic"] as? String,
      let logic = FilterLogic(rawValue: authorsLogicRaw)
    {
      self.authorsLogic = logic
    } else {
      self.authorsLogic = .all
    }
    self.genres = dict["genres"] as? [String]
    if let genresLogicRaw = dict["genresLogic"] as? String,
      let logic = FilterLogic(rawValue: genresLogicRaw)
    {
      self.genresLogic = logic
    } else {
      self.genresLogic = .all
    }
    self.tags = dict["tags"] as? [String]
    if let tagsLogicRaw = dict["tagsLogic"] as? String,
      let logic = FilterLogic(rawValue: tagsLogicRaw)
    {
      self.tagsLogic = logic
    } else {
      self.tagsLogic = .all
    }
    self.notableEntities = (dict["notableEntities"] as? [String])?.compactMap(
      NotableEntity.fromFilterKey)
    if let raw = dict["notableEntitiesLogic"] as? String,
      let logic = FilterLogic(rawValue: raw)
    {
      self.notableEntitiesLogic = logic
    } else {
      self.notableEntitiesLogic = .all
    }
    self.languages = dict["languages"] as? [String]
    if let languagesLogicRaw = dict["languagesLogic"] as? String,
      let logic = FilterLogic(rawValue: languagesLogicRaw)
    {
      self.languagesLogic = logic
    } else {
      self.languagesLogic = .all
    }
    self.ageRatings = dict["ageRatings"] as? [String]
    if let ageRatingsLogicRaw = dict["ageRatingsLogic"] as? String,
      let logic = FilterLogic(rawValue: ageRatingsLogicRaw)
    {
      self.ageRatingsLogic = logic
    } else {
      self.ageRatingsLogic = .all
    }
    self.releaseYears = dict["releaseYears"] as? [String]
    if let releaseYearsLogicRaw = dict["releaseYearsLogic"] as? String,
      let logic = FilterLogic(rawValue: releaseYearsLogicRaw)
    {
      self.releaseYearsLogic = logic
    } else {
      self.releaseYearsLogic = .all
    }
  }

  /// Create config for publisher filter
  static func forPublisher(_ publisher: String) -> MetadataFilterConfig {
    return MetadataFilterConfig(publishers: [publisher])
  }

  /// Create config for publishers filter
  static func forPublishers(_ publishers: [String]) -> MetadataFilterConfig {
    return MetadataFilterConfig(publishers: publishers)
  }

  /// Create config for author filter
  static func forAuthor(_ author: String) -> MetadataFilterConfig {
    return MetadataFilterConfig(authors: [author])
  }

  /// Create config for authors filter
  static func forAuthors(_ authors: [String]) -> MetadataFilterConfig {
    return MetadataFilterConfig(authors: authors)
  }

  /// Create config for genre filter
  static func forGenre(_ genre: String) -> MetadataFilterConfig {
    return MetadataFilterConfig(genres: [genre])
  }

  /// Create config for genres filter
  static func forGenres(_ genres: [String]) -> MetadataFilterConfig {
    return MetadataFilterConfig(genres: genres)
  }

  /// Create config for tag filter
  static func forTag(_ tag: String) -> MetadataFilterConfig {
    return MetadataFilterConfig(tags: [tag])
  }

  /// Create config for tags filter
  static func forTags(_ tags: [String]) -> MetadataFilterConfig {
    return MetadataFilterConfig(tags: tags)
  }

  static func forNotableEntity(_ entity: NotableEntity) -> MetadataFilterConfig {
    MetadataFilterConfig(notableEntities: [entity])
  }

  /// Create config for age rating filter
  static func forAgeRating(_ ageRating: String) -> MetadataFilterConfig {
    return MetadataFilterConfig(ageRatings: [ageRating])
  }

  /// Create config for release year filter
  static func forReleaseYear(_ releaseYear: String) -> MetadataFilterConfig {
    return MetadataFilterConfig(releaseYears: [releaseYear])
  }
}
