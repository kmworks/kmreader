//
// SmartListCardView.swift
//
//

import SwiftUI

struct SmartListCardView: View {
  let smartList: SmartList
  /// Text styles scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @State private var showDeleteConfirmation = false

  var body: some View {
    GridCardView(
      thumbnailId: smartList.id,
      thumbnailType: .smartList,
      title: smartList.name,
      cardWidth: cardWidth,
      navigationLink: NavDestination.smartListDetail(smartListId: smartList.id)
    ) {
      SmartListContextMenu(
        smartList: smartList,
        onDeleteRequested: {
          showDeleteConfirmation = true
        }
      )
    } detail: {
      Text(smartList.targetDisplayName)
    } overlayDetail: {
      Text(smartList.targetDisplayName)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .alert("Delete Smart List", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteSmartList()
      }
    } message: {
      Text("Are you sure you want to delete this smart list? This action cannot be undone.")
    }
  }

  private func deleteSmartList() {
    Task {
      do {
        try await SmartListService.deleteSmartList(smartListId: smartList.id)
        ErrorManager.shared.notify(
          message: String(localized: "notification.smartList.deleted", defaultValue: "Smart list deleted"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
