//
// LibraryScopeStore.swift
//
//

import SwiftUI

/// Shared loading for the library scope toolbar buttons. `refresh` hits the
/// server first; `load` only reads the local sidebar projection (used when the
/// projection changes notification fires).
@Observable
@MainActor
final class LibraryScopeStore {
  private(set) var libraries: [SidebarLibraryItem] = []
  /// Gates empty-library guidance until the first successful load, so guidance
  /// for the previous instance never flashes during a switch.
  private(set) var hasLoaded = false

  func refresh(instanceId: String) async {
    hasLoaded = false
    await LibraryManager.shared.refreshLibraries()
    await load(instanceId: instanceId)
  }

  func load(instanceId: String) async {
    do {
      let loaded = try await fetchLibraries(instanceId: instanceId)
      if libraries != loaded {
        libraries = loaded
      }
      hasLoaded = true
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func fetchLibraries(instanceId: String) async throws -> [SidebarLibraryItem] {
    guard !instanceId.isEmpty else {
      return []
    }
    let database = try await DatabaseOperator.database()
    return try await database.fetchSidebarLibraries(instanceId: instanceId)
  }
}
