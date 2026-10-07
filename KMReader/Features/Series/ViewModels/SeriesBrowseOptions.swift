//
// SeriesBrowseOptions.swift
//
//

import Foundation
import SwiftUI

nonisolated struct SeriesBrowseOptions: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var includeReadStatuses: Set<ReadStatus> = []
  var excludeReadStatuses: Set<ReadStatus> = []
  var includeSeriesStatuses: Set<SeriesStatus> = []
  var excludeSeriesStatuses: Set<SeriesStatus> = []
  var seriesStatusLogic: FilterLogic = .all
  var completeFilter: TriStateFilter<BoolTriStateFlag> = TriStateFilter()
  var oneshotFilter: TriStateFilter<BoolTriStateFlag> = TriStateFilter()
  var deletedFilter: TriStateFilter<BoolTriStateFlag> = TriStateFilter()
  var metadataFilter: MetadataFilterConfig = MetadataFilterConfig()
  var sortField: SeriesSortField = .name
  var sortDirection: SortDirection = .ascending

  var sortString: String {
    if sortField == .random {
      return "random"
    }
    return "\(sortField.rawValue),\(sortDirection.rawValue)"
  }

  var filtersCleared: SeriesBrowseOptions {
    var options = self
    options.includeReadStatuses = []
    options.excludeReadStatuses = []
    options.includeSeriesStatuses = []
    options.excludeSeriesStatuses = []
    options.seriesStatusLogic = .all
    options.completeFilter = TriStateFilter()
    options.oneshotFilter = TriStateFilter()
    options.deletedFilter = TriStateFilter()
    options.metadataFilter = MetadataFilterConfig()
    return options
  }

  var rawValue: String {
    let dict: [String: String] = [
      "includeReadStatuses": includeReadStatuses.map { $0.rawValue }.sorted().joined(
        separator: ","
      ),
      "excludeReadStatuses": excludeReadStatuses.map { $0.rawValue }.sorted().joined(
        separator: ","
      ),
      "includeSeriesStatuses": includeSeriesStatuses.map { $0.apiValue }.sorted().joined(
        separator: ","
      ),
      "excludeSeriesStatuses": excludeSeriesStatuses.map { $0.apiValue }.sorted().joined(
        separator: ","
      ),
      "seriesStatusLogic": seriesStatusLogic.rawValue,
      "completeFilter": completeFilter.storageValue,
      "oneshotFilter": oneshotFilter.storageValue,
      "deletedFilter": deletedFilter.storageValue,
      "metadataFilter": metadataFilter.rawValue,
      "sortField": sortField.rawValue,
      "sortDirection": sortDirection.rawValue,
    ]
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
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else {
      return nil
    }
    let includeReadRaw = dict["includeReadStatuses"] ?? ""
    let excludeReadRaw = dict["excludeReadStatuses"] ?? ""
    self.includeReadStatuses = Set(
      includeReadRaw.split(separator: ",").compactMap { ReadStatus(rawValue: String($0)) })
    self.excludeReadStatuses = Set(
      excludeReadRaw.split(separator: ",").compactMap { ReadStatus(rawValue: String($0)) })

    if includeReadStatuses.isEmpty && excludeReadStatuses.isEmpty,
      let legacy = dict["readStatusFilter"]
    {
      let tri = TriStateFilter<ReadStatus>.decode(legacy)
      if let value = tri.value {
        if tri.state == .exclude {
          excludeReadStatuses.insert(value)
        } else if tri.state == .include {
          includeReadStatuses.insert(value)
        }
      }
    }

    let includeRaw = dict["includeSeriesStatuses"] ?? ""
    let excludeRaw = dict["excludeSeriesStatuses"] ?? ""
    self.includeSeriesStatuses = Set(
      includeRaw.split(separator: ",").compactMap { SeriesStatus.fromAPIValue(String($0)) })
    self.excludeSeriesStatuses = Set(
      excludeRaw.split(separator: ",").compactMap { SeriesStatus.fromAPIValue(String($0)) })

    // Backward compatibility for legacy single-value tri-state
    if includeSeriesStatuses.isEmpty && excludeSeriesStatuses.isEmpty,
      let legacy = dict["seriesStatusFilter"]
    {
      let tri = TriStateFilter<SeriesStatus>.decode(legacy)
      if let value = tri.value {
        if tri.state == .exclude {
          excludeSeriesStatuses.insert(value)
        } else if tri.state == .include {
          includeSeriesStatuses.insert(value)
        }
      }
    }

    let logicRaw = dict["seriesStatusLogic"] ?? ""
    self.seriesStatusLogic =
      FilterLogic(rawValue: logicRaw)
      ?? (logicRaw == "AND" ? .all : logicRaw == "OR" ? .any : .all)
    self.completeFilter = TriStateFilter.decode(dict["completeFilter"])
    self.oneshotFilter = TriStateFilter.decode(dict["oneshotFilter"])
    self.deletedFilter = TriStateFilter.decode(dict["deletedFilter"])
    self.metadataFilter =
      MetadataFilterConfig(rawValue: dict["metadataFilter"] ?? "") ?? MetadataFilterConfig()
    self.sortField = SeriesSortField(rawValue: dict["sortField"] ?? "") ?? .name
    self.sortDirection = SortDirection(rawValue: dict["sortDirection"] ?? "") ?? .ascending
  }

  init() {}
}

extension SeriesBrowseOptions {
  /// Search filters for the condition-based series APIs; scoping ids (library,
  /// collection, …) stay with the caller, they vary per endpoint.
  nonisolated func toSearchFilters() -> SeriesSearchFilters {
    SeriesSearchFilters(
      includeReadStatuses: Array(includeReadStatuses),
      excludeReadStatuses: Array(excludeReadStatuses),
      includeSeriesStatuses: includeSeriesStatuses.map { $0.apiValue }.filter { !$0.isEmpty },
      excludeSeriesStatuses: excludeSeriesStatuses.map { $0.apiValue }.filter { !$0.isEmpty },
      seriesStatusLogic: seriesStatusLogic,
      oneshot: oneshotFilter.effectiveBool,
      deleted: deletedFilter.effectiveBool,
      complete: completeFilter.effectiveBool,
      publishers: metadataFilter.publishers,
      publishersLogic: metadataFilter.publishersLogic,
      authors: metadataFilter.authors,
      authorsLogic: metadataFilter.authorsLogic,
      genres: metadataFilter.genres,
      genresLogic: metadataFilter.genresLogic,
      tags: metadataFilter.tags,
      tagsLogic: metadataFilter.tagsLogic,
      languages: metadataFilter.languages,
      languagesLogic: metadataFilter.languagesLogic,
      ageRatings: metadataFilter.ageRatings?.compactMap { Int($0) },
      ageRatingsLogic: metadataFilter.ageRatingsLogic,
      releaseYears: metadataFilter.releaseYears?.compactMap { Int($0) },
      releaseYearsLogic: metadataFilter.releaseYearsLogic
    )
  }
}
