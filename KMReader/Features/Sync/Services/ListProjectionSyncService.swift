//
// ListProjectionSyncService.swift
//
//

import Foundation

/// Debounced projection sync for collections, read lists, and smart lists:
/// remote SSE changes collapse into one sync per family per window, then the
/// affected ids post so every surface reading the projection updates.
@MainActor
final class ListProjectionSyncService {
  static let shared = ListProjectionSyncService()

  private let debounceInterval: UInt64 = 5_000_000_000
  private var pendingCollectionSyncTask: Task<Void, Never>?
  private var pendingCollectionSyncIds: Set<String> = []
  private var pendingReadListSyncTask: Task<Void, Never>?
  private var pendingReadListSyncIds: Set<String> = []
  private var pendingSmartListSyncTask: Task<Void, Never>?
  private var pendingSmartListSyncIds: Set<String> = []
  private var pendingSmartListMembershipTask: Task<Void, Never>?

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

  /// Smart lists have no GRDB mirror, so the debounced event goes straight to
  /// the notification. Ids accumulate like the other families: observers
  /// (detail pages, member lists) filter the post by smartListId, so dropping
  /// an id here strands that surface until the next visit.
  func scheduleSmartListSync(smartListId: String) {
    pendingSmartListSyncIds.insert(smartListId)
    pendingSmartListSyncTask?.cancel()
    pendingSmartListSyncTask = Task {
      try? await Task.sleep(nanoseconds: debounceInterval)
      guard !Task.isCancelled else { return }
      let ids = pendingSmartListSyncIds.sorted()
      pendingSmartListSyncIds = []
      for id in ids {
        await ContentProjectionNotifier.postSmartListsDidChange(
          smartListId: id, refreshDelay: 0)
      }
    }
  }

  /// Read-status changes move smart-list membership without naming a list, so
  /// this collapse carries no id at all; member lists revalidate their window.
  func scheduleSmartListMembershipSync() {
    pendingSmartListMembershipTask?.cancel()
    pendingSmartListMembershipTask = Task {
      try? await Task.sleep(nanoseconds: debounceInterval)
      guard !Task.isCancelled else { return }
      await ContentProjectionNotifier.postSmartListMembershipDidChange()
    }
  }
}
