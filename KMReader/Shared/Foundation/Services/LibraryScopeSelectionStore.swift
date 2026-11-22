//
// LibraryScopeSelectionStore.swift
//
//

import SwiftUI

/// The session-only library scope shared by root browse surfaces. Pushed pages
/// keep their own temporary scope so drilling down never rewrites this selection.
@Observable
@MainActor
final class LibraryScopeSelectionStore {
  static let shared = LibraryScopeSelectionStore()

  var scope: LibraryBrowseScope = .all

  private init() {}

  func effectiveLibraryIds(pinned: [String]) -> [String] {
    scope.resolvedIds(pinned: pinned)
  }

  func reset(pinnedIds: [String]) {
    scope = pinnedIds.isEmpty ? .all : .pinned
  }

  func pinnedSelectionDidChange(from oldValue: [String], to newValue: [String]) {
    guard oldValue != newValue, newValue.isEmpty, scope == .pinned else { return }
    scope = .all
  }

  func librariesDidChange(_ libraries: [SidebarLibraryItem], pinnedIds: [String], instanceId: String) {
    guard AppConfig.current.instanceId == instanceId,
      let scopedId = scope.libraryId,
      !libraries.contains(where: { $0.libraryId == scopedId })
    else { return }
    reset(pinnedIds: pinnedIds)
  }
}
