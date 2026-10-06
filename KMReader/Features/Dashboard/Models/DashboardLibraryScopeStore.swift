//
// DashboardLibraryScopeStore.swift
//
//

import Foundation

/// The dashboard's session-only library scope: `.pinned` renders the pinned
/// aggregate (`dashboard.libraryIds`, empty = all libraries), `.all` ignores
/// the pins, `.library(id)` scopes every dashboard section to one library.
/// This is view state — it never persists and resets whenever the instance
/// changes.
@Observable
@MainActor
final class DashboardLibraryScopeStore {
  static let shared = DashboardLibraryScopeStore()

  var scope: LibraryBrowseScope = .pinned

  private init() {}

  func effectiveLibraryIds(pinned: [String]) -> [String] {
    scope.resolvedIds(pinned: pinned)
  }

  func reset() {
    scope = .pinned
  }
}
