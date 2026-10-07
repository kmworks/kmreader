//
// SmartListContextMenu.swift
//
//

import SwiftUI

struct SmartListContextMenu: View {
  let smartList: SmartList
  var onDeleteRequested: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()

  private var canDelete: Bool {
    smartList.ownerId == current.userId || current.isAdmin
  }

  var body: some View {
    Group {
      NavigationLink(value: NavDestination.smartListDetail(smartListId: smartList.id)) {
        Label("View Details", systemImage: AppIcon.details)
      }

      Divider()
      Button {
        refreshCover()
      } label: {
        Label("Refresh Cover", systemImage: AppIcon.refresh)
      }

      if canDelete, onDeleteRequested != nil {
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
