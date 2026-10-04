//
// CollectionCardView.swift
//
//

import SwiftUI

struct CollectionCardView: View {
  let item: CollectionDisplayItem
  var onMutationCompleted: (() -> Void)? = nil
  let onDeleteRequested: () -> Void
  /// Text styles scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @State private var showEditSheet = false

  var body: some View {
    GridCardView(
      thumbnailId: item.collectionId,
      thumbnailType: .collection,
      title: item.name,
      cardWidth: cardWidth,
      navigationLink: NavDestination.collectionDetail(collectionId: item.collectionId),
      titleLeadingSystemImage: item.isPinned ? "pin.fill" : nil
    ) {
      CollectionContextMenu(
        collectionId: item.collectionId,
        isPinned: item.isPinned,
        onDeleteRequested: {
          onDeleteRequested()
        },
        onEditRequested: {
          showEditSheet = true
        },
        onPinToggleRequested: {
          togglePinned()
        }
      )
    } detail: {
      Text("\(item.seriesCount) series")
    } overlayDetail: {
      Text("\(item.seriesCount) series")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sheet(isPresented: $showEditSheet) {
      CollectionEditSheet(collection: item.collection)
    }
  }

  private func togglePinned() {
    let nextPinned = !item.isPinned
    Task {
      try? await DatabaseOperator.database().setCollectionPinned(
        collectionId: item.collectionId,
        instanceId: item.instanceId,
        isPinned: nextPinned
      )
      onMutationCompleted?()
    }
  }
}
