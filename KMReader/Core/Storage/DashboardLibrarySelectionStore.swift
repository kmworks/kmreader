//
// DashboardLibrarySelectionStore.swift
//
//

import Foundation

enum DashboardLibrarySelectionStore {
  @MainActor private static var loadGeneration = 0

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
    loadGeneration += 1
    let generation = loadGeneration
    guard isCurrentLoad(generation, instanceId: instanceId) else { return }

    guard !instanceId.isEmpty else {
      applyCachedSelection([])
      LibraryScopeSelectionStore.shared.reset(pinnedIds: [])
      return
    }

    let cachedLibraryIds = AppConfig.dashboard.libraryIds
    let storedLibraryIds = await fetchStoredSelection(for: instanceId)
    guard isCurrentLoad(generation, instanceId: instanceId) else { return }

    if let storedLibraryIds {
      applyCachedSelection(storedLibraryIds)
    } else if preferCachedIfUnset && !cachedLibraryIds.isEmpty {
      await persistSelection(cachedLibraryIds, instanceId: instanceId)
      guard isCurrentLoad(generation, instanceId: instanceId) else { return }
      applyCachedSelection(cachedLibraryIds)
    } else {
      applyCachedSelection([])
    }
    guard isCurrentLoad(generation, instanceId: instanceId) else { return }
    LibraryScopeSelectionStore.shared.reset(pinnedIds: AppConfig.dashboard.libraryIds)
  }

  @MainActor
  static func updateCurrentSelection(_ libraryIds: [String]) {
    let instanceId = AppConfig.current.instanceId
    loadGeneration += 1
    applyCachedSelection(libraryIds)
    Task {
      await persistSelection(libraryIds, instanceId: instanceId)
    }
  }

  @MainActor
  private static func applyCachedSelection(_ libraryIds: [String]) {
    var dashboard = AppConfig.dashboard
    let previousLibraryIds = dashboard.libraryIds
    guard previousLibraryIds != libraryIds else { return }
    dashboard.libraryIds = libraryIds
    AppConfig.dashboard = dashboard
    DashboardSectionCacheStore.shared.reset()
    LibraryScopeSelectionStore.shared.pinnedSelectionDidChange(
      from: previousLibraryIds, to: libraryIds)
  }

  private static func isCurrentLoad(_ generation: Int, instanceId: String) -> Bool {
    generation == loadGeneration && AppConfig.current.instanceId == instanceId
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
