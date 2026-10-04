//
// ReadListOfflineActions.swift
//
//

import Foundation

/// Command layer for read-list offline downloads and policies, shared by the
/// context menu and the detail-page actions section.
struct ReadListOfflineActions {
  let readListId: String
  let instanceId: String
  var onMutationCompleted: (() -> Void)? = nil

  static let limitPresets: [Int] = [1, 3, 5, 10, 25, 50, 0]

  func updatePolicy(_ policy: OfflinePolicy) {
    Task {
      if policy != .manual {
        try? await SyncService.syncAllReadListBooks(readListId: readListId)
      }
      try? await DatabaseOperator.database().updateReadListOfflinePolicy(
        readListId: readListId,
        instanceId: instanceId,
        policy: policy
      )
      onMutationCompleted?()
    }
  }

  func updatePolicyAndLimit(_ policy: OfflinePolicy, limit: Int) {
    Task {
      try? await SyncService.syncAllReadListBooks(readListId: readListId)
      try? await DatabaseOperator.database().updateReadListOfflinePolicy(
        readListId: readListId,
        instanceId: instanceId,
        policy: policy,
        limit: limit
      )
      onMutationCompleted?()
    }
  }

  func perform(_ action: SeriesDownloadAction) {
    switch action {
    case .download:
      downloadAll()
    case .downloadUnread:
      downloadUnread(limit: 0)
    case .removeRead:
      removeRead()
    case .remove:
      removeAll()
    case .cancel:
      cancelDownload()
    }
  }

  func downloadAll() {
    Task {
      try? await SyncService.syncAllReadListBooks(readListId: readListId)
      try? await DatabaseOperator.database().downloadReadListOffline(
        readListId: readListId, instanceId: instanceId
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.readList.offlineDownloadQueued")
      )
      onMutationCompleted?()
    }
  }

  func downloadUnread(limit: Int) {
    Task {
      try? await SyncService.syncAllReadListBooks(readListId: readListId)
      try? await DatabaseOperator.database().downloadReadListUnreadOffline(
        readListId: readListId,
        instanceId: instanceId,
        limit: limit
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.readList.offlineDownloadQueued")
      )
      onMutationCompleted?()
    }
  }

  func removeRead() {
    Task {
      await OfflineManager.shared.removeReadListOfflineWithUndo(
        readListId: readListId, instanceId: instanceId, readOnly: true,
        message: String(localized: "notification.readList.offlineRemoved")
      )
      onMutationCompleted?()
    }
  }

  func removeAll() {
    Task {
      await OfflineManager.shared.removeReadListOfflineWithUndo(
        readListId: readListId, instanceId: instanceId, readOnly: false,
        message: String(localized: "notification.readList.offlineRemoved")
      )
      onMutationCompleted?()
    }
  }

  func cancelDownload() {
    Task {
      await OfflineManager.shared.cancelReadListDownload(
        readListId: readListId,
        instanceId: instanceId
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.book.downloadCancelled", defaultValue: "Download cancelled")
      )
      onMutationCompleted?()
    }
  }
}
