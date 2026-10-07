//
// SmartListFilterMapper.swift
//
//

import Foundation

/// Two-way mapping between a smart list's stored search document and the app's
/// browse options. The reverse direction only recognizes the condition shapes
/// BookSearch/SeriesSearch.buildCondition can emit; anything else sets `lossy`
/// so the caller can warn instead of silently dropping filters on save.
nonisolated enum SmartListFilterMapper {

  // MARK: - Forward: browse options -> search document

  static func bookSearch(
    libraryIds: [String], browseOpts: BookBrowseOptions, fullTextSearch: String
  ) -> BookSearch {
    var filters = browseOpts.toSearchFilters()
    filters.libraryIds = libraryIds.isEmpty ? nil : libraryIds
    let trimmed = fullTextSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    return BookSearch(
      condition: BookSearch.buildCondition(filters: filters),
      fullTextSearch: trimmed.isEmpty ? nil : trimmed)
  }

  static func seriesSearch(
    libraryIds: [String], browseOpts: SeriesBrowseOptions, fullTextSearch: String
  ) -> SeriesSearch {
    var filters = browseOpts.toSearchFilters()
    filters.libraryIds = libraryIds.isEmpty ? nil : libraryIds
    let trimmed = fullTextSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    return SeriesSearch(
      condition: SeriesSearch.buildCondition(filters: filters),
      fullTextSearch: trimmed.isEmpty ? nil : trimmed)
  }

  // MARK: - Reverse: search document -> browse options

  static func bookFilterState(from search: [String: JSONAny]?) -> (
    libraryIds: [String], browseOpts: BookBrowseOptions, fullTextSearch: String, lossy: Bool
  ) {
    var parser = SearchDocumentParser(target: .book)
    parser.parse(document: search)
    var opts = BookBrowseOptions()
    opts.includeReadStatuses = parser.includeReadStatuses
    opts.excludeReadStatuses = parser.excludeReadStatuses
    opts.oneshotFilter = parser.oneshotFilter
    opts.deletedFilter = parser.deletedFilter
    opts.metadataFilter = parser.metadata
    return (parser.libraryIds, opts, parser.fullTextSearch, parser.lossy)
  }

  static func seriesFilterState(from search: [String: JSONAny]?) -> (
    libraryIds: [String], browseOpts: SeriesBrowseOptions, fullTextSearch: String, lossy: Bool
  ) {
    var parser = SearchDocumentParser(target: .series)
    parser.parse(document: search)
    var opts = SeriesBrowseOptions()
    opts.includeReadStatuses = parser.includeReadStatuses
    opts.excludeReadStatuses = parser.excludeReadStatuses
    opts.includeSeriesStatuses = parser.includeSeriesStatuses
    opts.excludeSeriesStatuses = parser.excludeSeriesStatuses
    opts.seriesStatusLogic = parser.seriesStatusLogic
    opts.completeFilter = parser.completeFilter
    opts.oneshotFilter = parser.oneshotFilter
    opts.deletedFilter = parser.deletedFilter
    opts.metadataFilter = parser.metadata
    return (parser.libraryIds, opts, parser.fullTextSearch, parser.lossy)
  }
}

private nonisolated struct SearchDocumentParser {
  enum Target {
    case book
    case series
  }

  let target: Target

  var libraryIds: [String] = []
  var includeReadStatuses: Set<ReadStatus> = []
  var excludeReadStatuses: Set<ReadStatus> = []
  var includeSeriesStatuses: Set<SeriesStatus> = []
  var excludeSeriesStatuses: Set<SeriesStatus> = []
  var seriesStatusLogic: FilterLogic = .all
  var oneshotFilter = TriStateFilter<BoolTriStateFlag>()
  var deletedFilter = TriStateFilter<BoolTriStateFlag>()
  var completeFilter = TriStateFilter<BoolTriStateFlag>()
  var metadata = MetadataFilterConfig()
  var fullTextSearch = ""
  var lossy = false

  mutating func parse(document: [String: JSONAny]?) {
    guard let document else { return }
    if case .string(let text) = document["fullTextSearch"] {
      fullTextSearch = text
    }
    switch document["condition"] {
    case nil, .some(.null):
      return
    case .some(.dictionary(let condition)):
      if condition.isEmpty { return }
      parseRoot(condition)
    default:
      lossy = true
    }
  }

  /// The root is either a single bare condition, a homogeneous anyOf group, or
  /// the allOf list buildCondition emits when several filters combine.
  private mutating func parseRoot(_ condition: [String: JSONAny]) {
    if let allOf = groupElements(condition, wrapperKey: "allOf") {
      for element in allOf {
        guard case .dictionary(let node) = element else {
          lossy = true
          continue
        }
        parseNode(node)
      }
    } else if let anyOf = groupElements(condition, wrapperKey: "anyOf") {
      parseGroup(anyOf, logic: .any)
    } else if let leaf = leafParts(condition) {
      parseLeaf(leaf.key, leaf.body)
    } else {
      lossy = true
    }
  }

  private mutating func parseNode(_ node: [String: JSONAny]) {
    // A single releaseYears filter with .all logic surfaces here as a bare year
    // pair: buildCondition wraps years per-year in allOf, and a lone wrapper
    // becomes the root condition itself.
    if let year = releaseYear(fromPair: node) {
      guard target == .series else {
        lossy = true
        return
      }
      metadata.releaseYears = (metadata.releaseYears ?? []) + [String(year)]
      metadata.releaseYearsLogic = .all
      return
    }
    if let allOf = groupElements(node, wrapperKey: "allOf") {
      parseGroup(allOf, logic: .all)
    } else if let anyOf = groupElements(node, wrapperKey: "anyOf") {
      parseGroup(anyOf, logic: .any)
    } else if let leaf = leafParts(node) {
      parseLeaf(leaf.key, leaf.body)
    } else {
      lossy = true
    }
  }

  /// A wrapper group only has a browse-options representation when homogeneous:
  /// every element a release-year pair, or every element a leaf on the same key.
  private mutating func parseGroup(_ elements: [JSONAny], logic: FilterLogic) {
    guard !elements.isEmpty else {
      lossy = true
      return
    }

    var years: [Int] = []
    var allYearPairs = true
    for element in elements {
      guard case .dictionary(let dict) = element, let year = releaseYear(fromPair: dict) else {
        allYearPairs = false
        break
      }
      years.append(year)
    }
    if allYearPairs {
      guard target == .series else {
        lossy = true
        return
      }
      metadata.releaseYears = (metadata.releaseYears ?? []) + years.map(String.init)
      metadata.releaseYearsLogic = logic
      return
    }

    var leaves: [(key: String, body: [String: JSONAny])] = []
    for element in elements {
      guard case .dictionary(let dict) = element, let leaf = leafParts(dict) else {
        lossy = true
        return
      }
      leaves.append(leaf)
    }
    guard let key = leaves.first?.key, leaves.allSatisfy({ $0.key == key }) else {
      lossy = true
      return
    }
    parseLeafGroup(key: key, bodies: leaves.map { $0.body }, logic: logic)
  }

  /// Groups apply atomically: a malformed element skips the whole group so a
  /// partially applied filter never looks intentional.
  private mutating func parseLeafGroup(key: String, bodies: [[String: JSONAny]], logic: FilterLogic) {
    switch key {
    case "libraryId":
      // Multiple libraries are only ever ORed; an allOf of libraryId has no
      // browse-options representation.
      guard logic == .any else {
        lossy = true
        return
      }
      var ids: [String] = []
      for body in bodies {
        guard isOperator(body, "is"), let id = stringValue(body["value"]) else {
          lossy = true
          return
        }
        ids.append(id)
      }
      libraryIds.append(contentsOf: ids)
    case "readStatus":
      // buildCondition emits anyOf-is for includes and allOf-isNot for excludes;
      // the crossed combinations change semantics and cannot round-trip.
      let include = logic == .any && bodies.allSatisfy { isOperator($0, "is") }
      let exclude = logic == .all && bodies.allSatisfy { isOperator($0, "isNot") }
      guard include || exclude else {
        lossy = true
        return
      }
      var statuses: [ReadStatus] = []
      for body in bodies {
        guard let raw = stringValue(body["value"]), let status = ReadStatus(rawValue: raw) else {
          lossy = true
          return
        }
        statuses.append(status)
      }
      if include {
        includeReadStatuses.formUnion(statuses)
      } else {
        excludeReadStatuses.formUnion(statuses)
      }
    case "seriesStatus":
      guard target == .series else {
        lossy = true
        return
      }
      let include = bodies.allSatisfy { isOperator($0, "is") }
      let exclude = bodies.allSatisfy { isOperator($0, "isNot") }
      guard include != exclude else {
        lossy = true
        return
      }
      var statuses: [SeriesStatus] = []
      for body in bodies {
        guard let raw = stringValue(body["value"]), let status = SeriesStatus.fromAPIValue(raw)
        else {
          lossy = true
          return
        }
        statuses.append(status)
      }
      if include {
        includeSeriesStatuses.formUnion(statuses)
      } else {
        excludeSeriesStatuses.formUnion(statuses)
      }
      seriesStatusLogic = logic
    case "author", "tag", "genre", "publisher", "language", "ageRating":
      parseMetadataLeafGroup(key: key, bodies: bodies, logic: logic)
    default:
      lossy = true
    }
  }

  private mutating func parseLeaf(_ key: String, _ body: [String: JSONAny]) {
    switch key {
    case "libraryId":
      guard isOperator(body, "is"), let id = stringValue(body["value"]) else {
        lossy = true
        return
      }
      libraryIds.append(id)
    case "readStatus":
      guard let raw = stringValue(body["value"]), let status = ReadStatus(rawValue: raw) else {
        lossy = true
        return
      }
      if isOperator(body, "is") {
        includeReadStatuses.insert(status)
      } else if isOperator(body, "isNot") {
        excludeReadStatuses.insert(status)
      } else {
        lossy = true
      }
    case "seriesStatus":
      guard target == .series,
        let raw = stringValue(body["value"]),
        let status = SeriesStatus.fromAPIValue(raw)
      else {
        lossy = true
        return
      }
      if isOperator(body, "is") {
        includeSeriesStatuses.insert(status)
      } else if isOperator(body, "isNot") {
        excludeSeriesStatuses.insert(status)
      } else {
        lossy = true
        return
      }
      seriesStatusLogic = .all
    case "oneShot", "deleted", "complete":
      parseFlagLeaf(key: key, body: body)
    case "author", "tag", "genre", "publisher", "language", "ageRating":
      parseMetadataLeafGroup(key: key, bodies: [body], logic: .all)
    default:
      // Scoping ids (seriesId, readListId, collectionId), releaseDate outside a
      // year pair, and unknown keys have no browse-options representation.
      lossy = true
    }
  }

  /// isTrue maps to an included flag, isFalse to an excluded one — TriStateFilter
  /// only has a positive flag value, so exclusion flips the effective bool.
  private mutating func parseFlagLeaf(key: String, body: [String: JSONAny]) {
    if key == "complete", target != .series {
      lossy = true
      return
    }
    let filter: TriStateFilter<BoolTriStateFlag>
    if isOperator(body, "isTrue") {
      filter = .include(.yes)
    } else if isOperator(body, "isFalse") {
      filter = .exclude(.yes)
    } else {
      lossy = true
      return
    }
    switch key {
    case "oneShot":
      oneshotFilter = filter
    case "deleted":
      deletedFilter = filter
    default:
      completeFilter = filter
    }
  }

  private mutating func parseMetadataLeafGroup(
    key: String, bodies: [[String: JSONAny]], logic: FilterLogic
  ) {
    var values: [String] = []
    for body in bodies {
      guard isOperator(body, "is"), let value = metadataValue(key: key, from: body) else {
        lossy = true
        return
      }
      values.append(value)
    }
    switch key {
    case "author":
      metadata.authors = (metadata.authors ?? []) + values
      metadata.authorsLogic = logic
    case "tag":
      metadata.tags = (metadata.tags ?? []) + values
      metadata.tagsLogic = logic
    case "genre":
      metadata.genres = (metadata.genres ?? []) + values
      metadata.genresLogic = logic
    case "publisher":
      metadata.publishers = (metadata.publishers ?? []) + values
      metadata.publishersLogic = logic
    case "language":
      metadata.languages = (metadata.languages ?? []) + values
      metadata.languagesLogic = logic
    default:
      metadata.ageRatings = (metadata.ageRatings ?? []) + values
      metadata.ageRatingsLogic = logic
    }
  }

  /// Book filters only carry authors and tags; the remaining metadata kinds
  /// exist only in SeriesSearchFilters.
  private func metadataValue(key: String, from body: [String: JSONAny]) -> String? {
    switch key {
    case "author":
      guard case .dictionary(let value) = body["value"], case .string(let name) = value["name"]
      else { return nil }
      return name
    case "tag":
      return stringValue(body["value"])
    case "genre", "publisher", "language":
      guard target == .series else { return nil }
      return stringValue(body["value"])
    case "ageRating":
      guard target == .series else { return nil }
      switch body["value"] {
      case .int(let value):
        return String(value)
      case .double(let value):
        return Int(exactly: value).map(String.init)
      default:
        return nil
      }
    default:
      return nil
    }
  }

  /// buildCondition encodes year Y as after (Y-1)-12-31T12:00:00Z paired with
  /// before (Y+1)-01-01T12:00:00Z; any deviation from the exact pair shape is
  /// not a year filter.
  private func releaseYear(fromPair node: [String: JSONAny]) -> Int? {
    guard let pair = groupElements(node, wrapperKey: "allOf"), pair.count == 2,
      case .dictionary(let afterDict) = pair[0],
      case .dictionary(let beforeDict) = pair[1],
      let after = leafParts(afterDict), after.key == "releaseDate",
      let before = leafParts(beforeDict), before.key == "releaseDate",
      isOperator(after.body, "after"), isOperator(before.body, "before"),
      case .string(let afterDate) = after.body["dateTime"],
      case .string(let beforeDate) = before.body["dateTime"],
      let afterYear = yearPrefix(afterDate, suffix: "-12-31T12:00:00Z"),
      let beforeYear = yearPrefix(beforeDate, suffix: "-01-01T12:00:00Z"),
      afterYear + 1 == beforeYear - 1
    else { return nil }
    return afterYear + 1
  }

  private func yearPrefix(_ dateTime: String, suffix: String) -> Int? {
    guard dateTime.hasSuffix(suffix) else { return nil }
    return Int(dateTime.dropLast(suffix.count))
  }

  private func groupElements(_ dict: [String: JSONAny], wrapperKey: String) -> [JSONAny]? {
    guard dict.count == 1, case .array(let elements) = dict[wrapperKey] else { return nil }
    return elements
  }

  private func leafParts(_ dict: [String: JSONAny]) -> (key: String, body: [String: JSONAny])? {
    guard dict.count == 1, let entry = dict.first, case .dictionary(let body) = entry.value
    else { return nil }
    return (entry.key, body)
  }

  private func isOperator(_ body: [String: JSONAny], _ name: String) -> Bool {
    guard case .string(let op) = body["operator"] else { return false }
    return op == name
  }

  private func stringValue(_ value: JSONAny?) -> String? {
    guard case .string(let string) = value else { return nil }
    return string
  }
}
