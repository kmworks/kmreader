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
  /// The server's all-libraries aggregate row (admin-only metrics).
  private(set) var allLibrariesEntry: SidebarLibraryItem?
  /// Gates empty-library guidance until the first successful load, so guidance
  /// for the previous instance never flashes during a switch.
  private(set) var hasLoaded = false

  func refresh(instanceId: String) async {
    hasLoaded = false
    await LibraryManager.shared.refreshLibraries()
    await refreshMetrics(instanceId: instanceId)
  }

  /// Reloads the admin-only library metrics so scope headers follow the
  /// dashboard refresh. No-op for non-admin users and offline mode; servers
  /// without the stats endpoints show no metrics at all.
  func refreshMetrics(instanceId: String) async {
    if AppConfig.current.isAdmin, !AppConfig.isOffline, !instanceId.isEmpty {
      do {
        let metricsByLibrary = await LibraryMetricsLoader.shared.refreshMetrics(instanceId: instanceId)
        let database = try await DatabaseOperator.database()
        try await database.updateLibraryMetrics(
          instanceId: instanceId,
          metricsByLibrary: metricsByLibrary
        )
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
    await load(instanceId: instanceId)
  }

  func load(instanceId: String) async {
    do {
      let loaded = try await fetchLibraries(instanceId: instanceId)
      if libraries != loaded {
        libraries = loaded
      }
      let allEntry = try await fetchAllLibrariesEntry(instanceId: instanceId)
      if allLibrariesEntry != allEntry {
        allLibrariesEntry = allEntry
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

  private func fetchAllLibrariesEntry(instanceId: String) async throws -> SidebarLibraryItem? {
    guard !instanceId.isEmpty else {
      return nil
    }
    let database = try await DatabaseOperator.database()
    return try await database.fetchAllLibrariesItem(instanceId: instanceId)
  }
}
