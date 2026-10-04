//
// ReadListContextMenu.swift
//
//

import SwiftUI

struct ReadListContextMenu: View {
  let readListId: String
  let downloadStatus: SeriesDownloadStatus
  let offlinePolicy: OfflinePolicy
  let offlinePolicyLimit: Int
  let isPinned: Bool

  var onDeleteRequested: (() -> Void)? = nil
  var onEditRequested: (() -> Void)? = nil
  var onPinToggleRequested: (() -> Void)? = nil
  var onMutationCompleted: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  private var status: SeriesDownloadStatus {
    downloadStatus
  }

  private var limitPresets: [Int] {
    [1, 3, 5, 10, 25, 50, 0]
  }

  var body: some View {
    Group {
      NavigationLink(value: NavDestination.readListDetail(readListId: readListId)) {
        Label("View Details", systemImage: "info.circle")
      }

      Divider()
      Button {
        onPinToggleRequested?()
      } label: {
        Label(
          isPinned ? String(localized: "action.unpinFromTop") : String(localized: "action.pinToTop"),
          systemImage: isPinned ? "pin.slash" : "pin"
        )
      }

      ReadListStopReadingButton(readListId: readListId, instanceId: current.instanceId)

      if !isOffline {
        Divider()
        Menu {
          Button {
            updatePolicy(.manual)
          } label: {
            offlinePolicyLabel(.manual)
          }

          Menu {
            ForEach(limitPresets, id: \.self) { value in
              Button {
                updatePolicyAndLimit(.unreadOnly, limit: value)
              } label: {
                limitOptionLabel(policy: .unreadOnly, limit: value)
              }
            }
          } label: {
            offlinePolicyLabel(.unreadOnly)
          }

          Button {
            updatePolicy(.all)
          } label: {
            offlinePolicyLabel(.all)
          }
        } label: {
          Label("Offline Policy", systemImage: offlinePolicy.icon)
        }

        Menu {
          actionsView(actions: SeriesDownloadAction.availableReadListActions(for: status))
        } label: {
          Label("Offline", systemImage: status.icon ?? "icloud.and.arrow.down")
        }

        if current.isAdmin {
          Divider()
          Button {
            onEditRequested?()
          } label: {
            Label("Edit", systemImage: "pencil")
          }
        }

        Divider()
        Button {
          refreshCover()
        } label: {
          Label("Refresh Cover", systemImage: "arrow.clockwise")
        }
      }
    }
  }

  private func refreshCover() {
    Task {
      do {
        try await ThumbnailCache.refreshThumbnail(id: readListId, type: .readlist)
        ErrorManager.shared.notify(message: String(localized: "notification.readList.coverRefreshed"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private func actionsView(actions: [SeriesDownloadAction]) -> some View {
    ForEach(actions) { action in
      actionMenuItem(action: action)
    }
  }

  @ViewBuilder
  private func actionMenuItem(action: SeriesDownloadAction) -> some View {
    switch action {
    case .downloadUnread:
      Menu {
        downloadUnreadLimitOptions()
      } label: {
        Label(action.label(for: status), systemImage: action.icon(for: status))
      }
    default:
      Button(role: action.isDestructive ? .destructive : .none) {
        handleActionTap(action)
      } label: {
        Label(action.label(for: status), systemImage: action.icon(for: status))
      }
    }
  }

  private func handleActionTap(_ action: SeriesDownloadAction) {
    performAction(action)
  }

  private func handleDownloadUnreadTap(limit: Int) {
    downloadUnread(limit: limit)
  }

  private func updatePolicy(_ policy: OfflinePolicy) {
    Task {
      if policy != .manual {
        try? await SyncService.syncAllReadListBooks(readListId: readListId)
      }
      try? await DatabaseOperator.database().updateReadListOfflinePolicy(
        readListId: readListId,
        instanceId: current.instanceId,
        policy: policy
      )
      onMutationCompleted?()
    }
  }

  private func updatePolicyAndLimit(_ policy: OfflinePolicy, limit: Int) {
    Task {
      try? await SyncService.syncAllReadListBooks(readListId: readListId)
      try? await DatabaseOperator.database().updateReadListOfflinePolicy(
        readListId: readListId,
        instanceId: current.instanceId,
        policy: policy,
        limit: limit
      )
      onMutationCompleted?()
    }
  }

  @ViewBuilder
  private func offlinePolicyLabel(_ policy: OfflinePolicy) -> some View {
    let title = policy.title(limit: offlinePolicyLimit)
    Label {
      HStack(spacing: 4) {
        Text(policy == offlinePolicy ? title : policy.label)
        if policy == offlinePolicy {
          Image(systemName: "checkmark")
        }
      }
    } icon: {
      Image(systemName: policy.icon)
    }
  }

  @ViewBuilder
  private func limitOptionLabel(policy: OfflinePolicy, limit: Int) -> some View {
    let title = OfflinePolicy.limitTitle(limit)
    if offlinePolicy == policy && offlinePolicyLimit == limit {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }

  private func performAction(_ action: SeriesDownloadAction) {
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

  private func downloadAll() {
    Task {
      try? await SyncService.syncAllReadListBooks(readListId: readListId)
      try? await DatabaseOperator.database().downloadReadListOffline(
        readListId: readListId, instanceId: current.instanceId
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.readList.offlineDownloadQueued")
      )
      onMutationCompleted?()
    }
  }

  private func downloadUnread(limit: Int) {
    Task {
      try? await SyncService.syncAllReadListBooks(readListId: readListId)
      try? await DatabaseOperator.database().downloadReadListUnreadOffline(
        readListId: readListId,
        instanceId: current.instanceId,
        limit: limit
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.readList.offlineDownloadQueued")
      )
      onMutationCompleted?()
    }
  }

  private func removeRead() {
    Task {
      await OfflineManager.shared.removeReadListOfflineWithUndo(
        readListId: readListId, instanceId: current.instanceId, readOnly: true,
        message: String(localized: "notification.readList.offlineRemoved")
      )
      onMutationCompleted?()
    }
  }

  private func removeAll() {
    Task {
      await OfflineManager.shared.removeReadListOfflineWithUndo(
        readListId: readListId, instanceId: current.instanceId, readOnly: false,
        message: String(localized: "notification.readList.offlineRemoved")
      )
      onMutationCompleted?()
    }
  }

  private func cancelDownload() {
    Task {
      await OfflineManager.shared.cancelReadListDownload(
        readListId: readListId,
        instanceId: current.instanceId
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.book.downloadCancelled", defaultValue: "Download cancelled")
      )
      onMutationCompleted?()
    }
  }

  @ViewBuilder
  private func downloadUnreadLimitOptions() -> some View {
    ForEach(limitPresets, id: \.self) { value in
      Button {
        handleDownloadUnreadTap(limit: value)
      } label: {
        Text(OfflinePolicy.limitTitle(value))
      }
    }
  }
}
