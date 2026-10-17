//
// CollectionContextMenu.swift
//
//

import Foundation
import SwiftUI

struct CollectionContextMenu: View {
  let collectionId: String
  let isPinned: Bool
  var onDeleteRequested: (() -> Void)? = nil
  var onEditRequested: (() -> Void)? = nil
  var onPinToggleRequested: (() -> Void)? = nil
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  var body: some View {
    Group {
      Button {
        onPinToggleRequested?()
      } label: {
        Label(
          isPinned ? String(localized: "action.unpinFromTop") : String(localized: "action.pinToTop"),
          systemImage: isPinned ? "pin.slash" : "pin"
        )
      }

      if !isOffline {
        Divider()
        if current.isAdmin {
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

        if current.isAdmin, onDeleteRequested != nil {
          Divider()
          Button(role: .destructive) {
            deferMenuActionPresentation { onDeleteRequested?() }
          } label: {
            Label("Delete Collection", systemImage: AppIcon.delete)
          }
        }
      }
    }
  }

  private func refreshCover() {
    Task {
      do {
        try await ThumbnailCache.refreshThumbnail(id: collectionId, type: .collection)
        ErrorManager.shared.notify(message: String(localized: "notification.collection.coverRefreshed"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
