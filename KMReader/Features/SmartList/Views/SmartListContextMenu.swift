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

  private var canManage: Bool {
    smartList.ownerId == current.userId || current.isAdmin
  }

  var body: some View {
    Group {
      NavigationLink(value: NavDestination.smartListDetail(smartListId: smartList.id)) {
        Label("View Details", systemImage: AppIcon.details)
      }

      Divider()

      if canManage, onEditRequested != nil {
        Button {
          deferMenuActionPresentation { onEditRequested?() }
        } label: {
          Label("Edit Smart List", systemImage: AppIcon.edit)
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
