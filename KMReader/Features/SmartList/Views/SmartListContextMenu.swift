//
// SmartListContextMenu.swift
//
//

import SwiftUI

struct SmartListContextMenu: View {
  let smartList: SmartList
  var onEditRequested: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("pinnedSmartListIds") private var pinnedStore: PinnedSmartListIds = .init()

  private var canManage: Bool {
    smartList.ownerId == current.userId || current.isAdmin
  }

  private var isPinned: Bool {
    pinnedStore.isPinned(smartListId: smartList.id, instanceId: current.instanceId)
  }

  var body: some View {
    Group {
      Button {
        AppConfig.setSmartListPinned(
          smartListId: smartList.id, instanceId: current.instanceId, pinned: !isPinned)
      } label: {
        Label(
          isPinned ? String(localized: "action.unpinFromTop") : String(localized: "action.pinToTop"),
          systemImage: isPinned ? "pin.slash" : "pin"
        )
      }

      if !isOffline {
        Divider()

        if canManage, onEditRequested != nil {
          Button {
            deferMenuActionPresentation { onEditRequested?() }
          } label: {
            Label("Edit", systemImage: AppIcon.edit)
          }
        }

        Button {
          refreshCover()
        } label: {
          Label("Refresh Cover", systemImage: AppIcon.refresh)
        }

        if canManage, onDeleteRequested != nil {
          Divider()
          Button(role: .destructive) {
            deferMenuActionPresentation { onDeleteRequested?() }
          } label: {
            Label("Delete Smart List", systemImage: AppIcon.delete)
          }
        }
      }
    }
  }

  private func refreshCover() {
    Task {
      do {
        try await ThumbnailCache.refreshThumbnail(id: smartList.id, type: .smartList)
        ErrorManager.shared.notify(
          message: String(localized: "notification.smartList.coverRefreshed", defaultValue: "Cover refreshed"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
