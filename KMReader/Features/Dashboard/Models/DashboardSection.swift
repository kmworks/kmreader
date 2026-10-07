//
// DashboardSection.swift
//
//

import Foundation
import SwiftUI

enum DashboardSectionContentKind: Sendable {
  case books
  case series
}

/// Card presentation of a dashboard section: large showcase cards, medium and
/// small utility cards, or horizontal cards. Each section has a default kind
/// that the user can override from the section header menu.
enum DashboardCardKind: String, Codable, Sendable, CaseIterable {
  case large
  case medium
  case small
  case horizontal

  var title: LocalizedStringKey {
    switch self {
    case .large:
      return "dashboard.cardKind.large"
    case .medium:
      return "dashboard.cardKind.medium"
    case .small:
      return "dashboard.cardKind.small"
    case .horizontal:
      return "dashboard.cardKind.horizontal"
    }
  }

  var icon: String {
    switch self {
    case .large:
      return "square.grid.2x2"
    case .medium:
      return "rectangle.grid.3x2"
    case .small:
      return "square.grid.3x3"
    case .horizontal:
      return "rectangle.lefthalf.inset.filled"
    }
  }

  var cardWidth: CGFloat {
    switch self {
    case .large:
      return LayoutConfig.dashboardLargeCardWidth
    case .medium:
      return LayoutConfig.dashboardMediumCardWidth
    case .small:
      return LayoutConfig.dashboardSmallCardWidth
    case .horizontal:
      return LayoutConfig.horizontalCardWidth
    }
  }
}

enum DashboardSection: String, CaseIterable, Identifiable, Codable, Sendable {
  /// First by default: for users who opted in, a read list's next book is
  /// where reading continues, ahead of the per-series suggestions below it.
  case readListsInProgress = "readListsInProgress"
  case keepReading = "keepReading"
  case onDeck = "onDeck"
  case recentlyReleasedBooks = "recentlyReleasedBooks"
  case recentlyAddedBooks = "recentlyAddedBooks"
  case recentlyAddedSeries = "recentlyAddedSeries"
  case recentlyUpdatedSeries = "recentlyUpdatedSeries"
  case recentlyReadBooks = "recentlyReadBooks"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .keepReading:
      return String(localized: "dashboard.keepReading")
    case .onDeck:
      return String(localized: "dashboard.onDeck")
    case .readListsInProgress:
      return String(localized: "dashboard.readListsInProgress")
    case .recentlyReleasedBooks:
      return String(localized: "dashboard.recentlyReleasedBooks")
    case .recentlyAddedBooks:
      return String(localized: "dashboard.recentlyAddedBooks")
    case .recentlyUpdatedSeries:
      return String(localized: "dashboard.recentlyUpdatedSeries")
    case .recentlyAddedSeries:
      return String(localized: "dashboard.recentlyAddedSeries")
    case .recentlyReadBooks:
      return String(localized: "dashboard.recentlyReadBooks")
    }
  }

  var icon: String {
    switch self {
    case .keepReading:
      return "book.fill"
    case .onDeck:
      return "bookmark.fill"
    case .readListsInProgress:
      return "list.number"
    case .recentlyReleasedBooks:
      return "calendar.badge.clock"
    case .recentlyAddedBooks:
      return "sparkles"
    case .recentlyUpdatedSeries:
      return "arrow.triangle.2.circlepath.circle.fill"
    case .recentlyAddedSeries:
      return "square.stack.3d.up.fill"
    case .recentlyReadBooks:
      return "checkmark.circle.fill"
    }
  }

  var contentKind: DashboardSectionContentKind {
    switch self {
    case .keepReading, .onDeck, .recentlyReadBooks, .recentlyReleasedBooks, .recentlyAddedBooks,
      .readListsInProgress:
      return .books
    case .recentlyUpdatedSeries, .recentlyAddedSeries:
      return .series
    }
  }

  var cardKind: DashboardCardKind {
    switch self {
    case .keepReading, .readListsInProgress:
      return .horizontal
    case .onDeck, .recentlyReleasedBooks, .recentlyAddedBooks, .recentlyUpdatedSeries:
      return .large
    case .recentlyReadBooks, .recentlyAddedSeries:
      return .small
    }
  }

  /// Card kinds the user can pick for this section. Series has no horizontal
  /// card.
  var availableCardKinds: [DashboardCardKind] {
    switch contentKind {
    case .books:
      return [.large, .medium, .small, .horizontal]
    case .series:
      return [.large, .medium, .small]
    }
  }

  var widgetDataTarget: DashboardWidgetDataTarget? {
    switch self {
    case .keepReading:
      return .keepReading
    case .recentlyAddedBooks:
      return .recentlyAdded
    case .recentlyUpdatedSeries:
      return .recentlyUpdatedSeries
    default:
      return nil
    }
  }

  var supportsDownloadLatest: Bool {
    switch self {
    case .keepReading, .onDeck, .recentlyReleasedBooks, .recentlyAddedBooks:
      return true
    default:
      return false
    }
  }

  var supportsDownloadAll: Bool {
    switch self {
    case .keepReading, .onDeck:
      return true
    default:
      return false
    }
  }

  /// Sections a new or reset dashboard shows. Read Lists in Progress belongs to
  /// an opt-in feature, so its setting adds and removes it instead.
  nonisolated static var defaultSections: [DashboardSection] {
    allCases.filter { $0 != .readListsInProgress }
  }

  /// Whether the section can be shown at all: Read Lists in Progress needs its
  /// opt-in setting.
  nonisolated var isAvailable: Bool {
    self != .readListsInProgress || AppConfig.readListContinuationEnabled
  }

  func fetchBooks(libraryIds: [String], page: Int, size: Int) async throws -> Page<Book>? {
    switch self {
    case .keepReading:
      let condition = BookSearch.buildCondition(
        filters: BookSearchFilters(
          libraryIds: libraryIds,
          includeReadStatuses: [ReadStatus.inProgress]
        )
      )
      let search = BookSearch(condition: condition)
      return try await SyncService.syncBooksList(
        search: search,
        page: page,
        size: size,
        sort: "readProgress.readDate,desc"
      )

    case .onDeck:
      return try await SyncService.syncBooksOnDeck(
        libraryIds: libraryIds,
        page: page,
        size: size
      )

    case .recentlyReadBooks:
      return try await SyncService.syncRecentlyReadBooks(
        libraryIds: libraryIds,
        page: page,
        size: size
      )

    case .recentlyReleasedBooks:
      return try await SyncService.syncRecentlyReleasedBooks(
        libraryIds: libraryIds,
        page: page,
        size: size
      )

    case .recentlyAddedBooks:
      return try await SyncService.syncRecentlyAddedBooks(
        libraryIds: libraryIds,
        page: page,
        size: size
      )

    default:
      return nil
    }
  }

  func fetchSeries(libraryIds: [String], page: Int, size: Int) async throws -> Page<Series>? {
    switch self {
    case .recentlyAddedSeries:
      return try await SyncService.syncNewSeries(
        libraryIds: libraryIds,
        page: page,
        size: size
      )

    case .recentlyUpdatedSeries:
      return try await SyncService.syncUpdatedSeries(
        libraryIds: libraryIds,
        page: page,
        size: size
      )

    default:
      return nil
    }
  }

  func fetchOfflineBookIds(libraryIds: [String], offset: Int, limit: Int) async -> [String] {
    guard let database = try? await DatabaseOperator.database() else { return [] }
    return await database.fetchDashboardOfflineBookIds(
      section: self,
      libraryIds: libraryIds,
      offset: offset,
      limit: limit
    )
  }

  func fetchOfflineSeriesIds(libraryIds: [String], offset: Int, limit: Int) async -> [String] {
    guard let database = try? await DatabaseOperator.database() else { return [] }
    return await database.fetchDashboardOfflineSeriesIds(
      section: self,
      libraryIds: libraryIds,
      offset: offset,
      limit: limit
    )
  }
}

// RawRepresentable wrapper for [DashboardSection] and libraryIds to use with @AppStorage
struct DashboardConfiguration: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var sections: [DashboardSection]
  var libraryIds: [String]
  var cardKindOverrides: [DashboardSection: DashboardCardKind]

  nonisolated init(
    sections: [DashboardSection] = DashboardSection.defaultSections,
    libraryIds: [String] = [],
    cardKindOverrides: [DashboardSection: DashboardCardKind] = [:]
  ) {
    self.sections = sections
    self.libraryIds = libraryIds
    self.cardKindOverrides = cardKindOverrides
  }

  /// Effective card kind for a section: user override, else the section default.
  /// Overrides no longer available for the section are ignored.
  func cardKind(for section: DashboardSection) -> DashboardCardKind {
    if let override = cardKindOverrides[section], section.availableCardKinds.contains(override) {
      return override
    }
    return section.cardKind
  }

  mutating func setCardKind(_ kind: DashboardCardKind, for section: DashboardSection) {
    cardKindOverrides[section] = kind
  }

  /// Shows a section at its position in `DashboardSection.allCases`: before the
  /// first shown section that comes after it.
  mutating func insertSection(_ section: DashboardSection) {
    guard !sections.contains(section), let order = DashboardSection.allCases.firstIndex(of: section)
    else { return }
    let index =
      sections.firstIndex { (DashboardSection.allCases.firstIndex(of: $0) ?? 0) > order } ?? sections.count
    sections.insert(section, at: index)
  }

  mutating func removeSection(_ section: DashboardSection) {
    sections.removeAll { $0 == section }
  }

  nonisolated var rawValue: String {
    let dict: [String: Any] = [
      "sections": sections.map { $0.rawValue },
      "libraryIds": libraryIds,
      "cardKindOverrides": Dictionary(
        uniqueKeysWithValues: cardKindOverrides.map { ($0.key.rawValue, $0.value.rawValue) }),
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
      self.sections = DashboardSection.defaultSections
      self.libraryIds = []
      self.cardKindOverrides = [:]
      return
    }
    guard let data = rawValue.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      self.sections = DashboardSection.defaultSections
      self.libraryIds = []
      self.cardKindOverrides = [:]
      return
    }

    // Parse sections
    if let sectionsArray = dict["sections"] as? [String] {
      self.sections = sectionsArray.compactMap { DashboardSection(rawValue: $0) }
      if self.sections.isEmpty {
        self.sections = DashboardSection.defaultSections
      }
    } else {
      self.sections = DashboardSection.defaultSections
    }

    // Parse libraryIds
    if let libraryIdsArray = dict["libraryIds"] as? [String] {
      self.libraryIds = libraryIdsArray
    } else {
      self.libraryIds = []
    }

    // Parse card kind overrides
    if let overridesDict = dict["cardKindOverrides"] as? [String: String] {
      self.cardKindOverrides = Dictionary(
        uniqueKeysWithValues: overridesDict.compactMap { key, value in
          guard let section = DashboardSection(rawValue: key),
            let kind = DashboardCardKind(rawValue: value)
          else { return nil }
          return (section, kind)
        })
    } else {
      self.cardKindOverrides = [:]
    }
  }
}
