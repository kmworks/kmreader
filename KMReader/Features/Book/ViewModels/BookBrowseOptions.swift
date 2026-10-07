//
// BookBrowseOptions.swift
//
//

import Foundation
import SwiftUI

nonisolated struct BookBrowseOptions: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var includeReadStatuses: Set<ReadStatus> = []
  var excludeReadStatuses: Set<ReadStatus> = []
  var oneshotFilter: TriStateFilter<BoolTriStateFlag> = TriStateFilter()
  var deletedFilter: TriStateFilter<BoolTriStateFlag> = TriStateFilter()
  var metadataFilter: MetadataFilterConfig = MetadataFilterConfig()
  var sortField: BookSortField = .series
  var sortDirection: SortDirection = .ascending

  var sortString: String {
    return "\(sortField.rawValue),\(sortDirection.rawValue)"
  }

  /// One `sort` query value per server key: repeated params are the portable form,
  /// a folded single value relies on Spring-specific parsing.
  var sortQueryValues: [String] {
    sortField.serverSortKeys.map { "\($0),\(sortDirection.rawValue)" }
  }

  /// Whether a pure reading-progress change can alter list membership or
  /// ordering. When false, item rows self-update from GRDB and the ID list
  /// does not need to be revalidated at all.
  var isSensitiveToReadingProgress: Bool {
    sortField == .dateRead || !includeReadStatuses.isEmpty || !excludeReadStatuses.isEmpty
  }

  var filtersCleared: BookBrowseOptions {
    var options = self
    options.includeReadStatuses = []
    options.excludeReadStatuses = []
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
    let includeRaw = dict["includeReadStatuses"] ?? ""
    let excludeRaw = dict["excludeReadStatuses"] ?? ""
    self.includeReadStatuses = Set(
      includeRaw.split(separator: ",").compactMap { ReadStatus(rawValue: String($0)) })
    self.excludeReadStatuses = Set(
      excludeRaw.split(separator: ",").compactMap { ReadStatus(rawValue: String($0)) })

    self.oneshotFilter = TriStateFilter.decode(dict["oneshotFilter"])
    self.deletedFilter = TriStateFilter.decode(dict["deletedFilter"])
    self.metadataFilter =
      MetadataFilterConfig(rawValue: dict["metadataFilter"] ?? "") ?? MetadataFilterConfig()

    // backward compatibility with legacy tri-state
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

    self.sortField = BookSortField(rawValue: dict["sortField"] ?? "") ?? .series
    self.sortDirection = SortDirection(rawValue: dict["sortDirection"] ?? "") ?? .ascending
  }

  init() {}
}

extension BookBrowseOptions {
  /// Search filters for the condition-based book APIs; scoping ids (library,
  /// series, …) stay with the caller, they vary per endpoint.
  nonisolated func toSearchFilters() -> BookSearchFilters {
    BookSearchFilters(
      includeReadStatuses: Array(includeReadStatuses),
      excludeReadStatuses: Array(excludeReadStatuses),
      oneshot: oneshotFilter.effectiveBool,
      deleted: deletedFilter.effectiveBool,
      authors: metadataFilter.authors,
      authorsLogic: metadataFilter.authorsLogic,
      tags: metadataFilter.tags,
      tagsLogic: metadataFilter.tagsLogic
    )
  }
}
