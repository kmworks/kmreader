//
// DashboardLibrarySelectionStore.swift
//
//

import Foundation

enum DashboardLibrarySelectionStore {
  static func persistSelection(_ libraryIds: [String], instanceId: String) async {
    guard !instanceId.isEmpty else { return }
    do {
      let database = try await DatabaseOperator.database()
      try await database.updateSelectedLibraryIds(libraryIds, instanceId: instanceId)
    } catch {
      AppLogger(.database).error(
        "Failed to persist dashboard library selection: \(error.localizedDescription)")
    }
  }

  @MainActor
  static func persistCurrentSelection() async {
    let instanceId = AppConfig.current.instanceId
    let libraryIds = AppConfig.dashboard.libraryIds
    await persistSelection(libraryIds, instanceId: instanceId)
  }

  @MainActor
  static func loadSelection(for instanceId: String, preferCachedIfUnset: Bool = false) async {
    DashboardLibraryScopeStore.shared.reset()
    guard !instanceId.isEmpty else {
      applyCachedSelection([])
      return
    }

    let cachedLibraryIds = AppConfig.dashboard.libraryIds
    let storedLibraryIds = await fetchStoredSelection(for: instanceId)

    if let storedLibraryIds {
      applyCachedSelection(storedLibraryIds)
      return
    }

    if preferCachedIfUnset && !cachedLibraryIds.isEmpty {
      await persistSelection(cachedLibraryIds, instanceId: instanceId)
      applyCachedSelection(cachedLibraryIds)
      return
    }

    applyCachedSelection([])
  }

  @MainActor
  static func updateCurrentSelection(_ libraryIds: [String]) {
    let instanceId = AppConfig.current.instanceId
    applyCachedSelection(libraryIds)
    Task {
      await persistSelection(libraryIds, instanceId: instanceId)
    }
  }

  @MainActor
  private static func applyCachedSelection(_ libraryIds: [String]) {
    var dashboard = AppConfig.dashboard
    guard dashboard.libraryIds != libraryIds else { return }
    dashboard.libraryIds = libraryIds
    AppConfig.dashboard = dashboard
    DashboardSectionCacheStore.shared.reset()
  }

  private static func fetchStoredSelection(for instanceId: String) async -> [String]? {
    do {
      let database = try await DatabaseOperator.database()
      return try await database.fetchSelectedLibraryIds(instanceId: instanceId)
    } catch {
      AppLogger(.database).error(
        "Failed to load dashboard library selection: \(error.localizedDescription)")
      return nil
    }
  }
}
