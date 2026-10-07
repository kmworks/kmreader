//
// ListProjectionSyncService.swift
//
//

import Foundation

/// Debounced projection sync for collections and read lists: remote SSE
/// changes collapse into one full sync per family per window, then the
/// affected ids post so every surface reading the projection updates.
@MainActor
final class ListProjectionSyncService {
  static let shared = ListProjectionSyncService()

  private let debounceInterval: UInt64 = 5_000_000_000
  private var pendingCollectionSyncTask: Task<Void, Never>?
  private var pendingCollectionSyncIds: Set<String> = []
  private var pendingReadListSyncTask: Task<Void, Never>?
  private var pendingReadListSyncIds: Set<String> = []

  private init() {}

  func scheduleCollectionSync(collectionId: String) {
    pendingCollectionSyncIds.insert(collectionId)
    pendingCollectionSyncTask?.cancel()
    pendingCollectionSyncTask = Task {
      try? await Task.sleep(nanoseconds: debounceInterval)
      guard !Task.isCancelled else { return }
      let ids = Array(pendingCollectionSyncIds)
      pendingCollectionSyncIds = []
      await SyncService.syncCollections(instanceId: AppConfig.current.instanceId)
      await ContentProjectionNotifier.postCollectionsDidChange(collectionIds: ids)
    }
  }

  func scheduleReadListSync(readListId: String) {
    pendingReadListSyncIds.insert(readListId)
    pendingReadListSyncTask?.cancel()
    pendingReadListSyncTask = Task {
      try? await Task.sleep(nanoseconds: debounceInterval)
      guard !Task.isCancelled else { return }
      let ids = Array(pendingReadListSyncIds)
      pendingReadListSyncIds = []
      await SyncService.syncReadLists(instanceId: AppConfig.current.instanceId)
      await ContentProjectionNotifier.postReadListsDidChange(readListIds: ids)
    }
  }
}
