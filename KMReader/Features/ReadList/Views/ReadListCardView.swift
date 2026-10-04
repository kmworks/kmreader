//
// ReadListCardView.swift
//
//

import SwiftUI

struct ReadListCardView: View {
  let item: ReadListDisplayItem
  var onMutationCompleted: (() -> Void)? = nil
  let onDeleteRequested: () -> Void
  /// Text styles scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @State private var showEditSheet = false

  var body: some View {
    GridCardView(
      thumbnailId: item.readListId,
      thumbnailType: .readlist,
      title: item.name,
      cardWidth: cardWidth,
      navigationLink: NavDestination.readListDetail(readListId: item.readListId),
      titleLeadingSystemImage: item.isPinned ? "pin.fill" : nil
    ) {
      ReadListContextMenu(
        readListId: item.readListId,
        downloadStatus: item.downloadStatus,
        offlinePolicy: item.offlinePolicy,
        offlinePolicyLimit: item.offlinePolicyLimit,
        isPinned: item.isPinned,
        onDeleteRequested: {
          onDeleteRequested()
        },
        onEditRequested: {
          showEditSheet = true
        },
        onPinToggleRequested: {
          togglePinned()
        },
        onMutationCompleted: onMutationCompleted
      )
    } detail: {
      Text("\(item.bookCount) books")
    } overlayDetail: {
      Text("\(item.bookCount) books")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sheet(isPresented: $showEditSheet) {
      ReadListEditSheet(readList: item.readList)
    }
  }

  private func togglePinned() {
    let nextPinned = !item.isPinned
    Task {
      try? await DatabaseOperator.database().setReadListPinned(
        readListId: item.readListId,
        instanceId: item.instanceId,
        isPinned: nextPinned
      )
      onMutationCompleted?()
    }
  }
}
