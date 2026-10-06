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

  private var offlineActions: ReadListOfflineActions {
    ReadListOfflineActions(
      readListId: readListId,
      instanceId: current.instanceId,
      onMutationCompleted: onMutationCompleted
    )
  }

  var body: some View {
    Group {
      NavigationLink(value: NavDestination.readListDetail(readListId: readListId)) {
        Label("View Details", systemImage: AppIcon.details)
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
          ReadListOfflinePolicyMenuItems(
            policy: offlinePolicy,
            offlinePolicyLimit: offlinePolicyLimit,
            actions: offlineActions
          )
        } label: {
          Label("Offline Policy", systemImage: offlinePolicy.icon)
        }

        Menu {
          ReadListDownloadActionMenuItems(status: downloadStatus, actions: offlineActions)
        } label: {
          Label("Offline", systemImage: downloadStatus.icon ?? AppIcon.download)
        }

        if current.isAdmin {
          Divider()
          Button {
            onEditRequested?()
          } label: {
            Label("Edit", systemImage: AppIcon.edit)
          }

          if onDeleteRequested != nil {
            Divider()
            Button(role: .destructive) {
              deferMenuActionPresentation { onDeleteRequested?() }
            } label: {
              Label("Delete Read List", systemImage: AppIcon.delete)
            }
          }
        }

        Divider()
        Button {
          refreshCover()
        } label: {
          Label("Refresh Cover", systemImage: AppIcon.refresh)
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
}
