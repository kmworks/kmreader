//
// DashboardSectionRefreshNotifier.swift
//
//

import Foundation

extension Notification.Name {
  static let dashboardSectionsShouldReload = Notification.Name("DashboardSectionsShouldReload")
}

nonisolated enum DashboardSectionRefreshNotifier {
  static let sectionsUserInfoKey = "sections"
  static let sourceUserInfoKey = "source"
  static let reasonUserInfoKey = "reason"
  static let commandUserInfoKey = "command"

  static let bookContentSections: Set<DashboardSection> = [
    .keepReading,
    .onDeck,
    .recentlyReadBooks,
    .recentlyReleasedBooks,
    .recentlyAddedBooks,
  ]

  static let seriesContentSections: Set<DashboardSection> = [
    .recentlyAddedSeries,
    .recentlyUpdatedSeries,
  ]

  static let readingProgressSections: Set<DashboardSection> = [
    .keepReading,
    .onDeck,
    .readListsInProgress,
    .recentlyReadBooks,
  ]

  static let readStatusSections: Set<DashboardSection> =
    readingProgressSections
    .union(seriesContentSections)

  static func postSeriesContentChanged(source: DashboardRefreshSource, reason: String) async {
    await post(sections: seriesContentSections, source: source, reason: reason)
  }

  static func postReadStatusChanged(source: DashboardRefreshSource, reason: String) async {
    await post(sections: readStatusSections, source: source, reason: reason)
  }

  static func post(
    sections: Set<DashboardSection>,
    source: DashboardRefreshSource,
    reason: String
  ) async {
    guard !sections.isEmpty else { return }

    await DashboardRefreshCoordinator.shared.requestRefresh(
      sections: sections,
      source: source,
      reason: reason
    )
  }

  static func postAll(source: DashboardRefreshSource, reason: String) async {
    await DashboardRefreshCoordinator.shared.requestRefresh(
      sections: nil,
      source: source,
      reason: reason
    )
  }

  static func sectionsForBookProjectionChange(
    reasons: Set<ContentProjectionChangeReason>
  ) -> Set<DashboardSection> {
    if reasons.contains(.content) {
      return bookContentSections.union(seriesContentSections)
    }
    return []
  }

  static func sectionsForSeriesProjectionChange(
    reasons: Set<ContentProjectionChangeReason>
  ) -> Set<DashboardSection> {
    if reasons.contains(.content) {
      return seriesContentSections
    }
    return []
  }

  @MainActor
  static func postReload(command: DashboardSectionReloadCommand) {
    var userInfo: [String: Any] = [
      commandUserInfoKey: command,
      sourceUserInfoKey: command.source,
      reasonUserInfoKey: command.reason,
    ]
    if let sections = command.sections {
      userInfo[sectionsUserInfoKey] = sections
    }

    NotificationCenter.default.post(
      name: .dashboardSectionsShouldReload,
      object: nil,
      userInfo: userInfo
    )
  }

  static func reloadCommand(from notification: Notification) -> DashboardSectionReloadCommand? {
    if let command = notification.userInfo?[commandUserInfoKey] as? DashboardSectionReloadCommand {
      return command
    }

    let source =
      notification.userInfo?[sourceUserInfoKey] as? DashboardRefreshSource
      ?? .auto
    let reason =
      notification.userInfo?[reasonUserInfoKey] as? String
      ?? "Dashboard section reload"

    if let sections = notification.userInfo?[sectionsUserInfoKey] as? Set<DashboardSection> {
      return DashboardSectionReloadCommand(
        id: UUID(),
        source: source,
        sections: sections,
        reason: reason
      )
    }

    return DashboardSectionReloadCommand(
      id: UUID(),
      source: source,
      sections: nil,
      reason: reason
    )
  }
}
