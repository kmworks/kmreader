//
// CollectionHorizontalCardView.swift
//
//

import SwiftUI

@MainActor
struct CollectionHorizontalCardView: View {
  let item: CollectionDisplayItem
  var coverWidth: CGFloat = 56
  var onChanged: () -> Void = {}
  let onDeleteRequested: () -> Void

  @State private var showEditSheet = false

  private var collectionContextMenu: some View {
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
  }

  var body: some View {
    HorizontalCardSkeleton(
      thumbnailId: item.collectionId,
      thumbnailType: .collection,
      coverWidth: coverWidth,
      navigationLink: NavDestination.collectionDetail(collectionId: item.collectionId)
    ) { palette in
      Spacer(minLength: 0)

      Text(item.name)
        .font(.system(size: LayoutConfig.horizontalCardFontSize, weight: .semibold))
        .foregroundColor(palette.titleColor)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: 4) {
        Text("\(item.seriesCount) series")
          .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))

        Text(item.lastModifiedDate.formattedMediumDate)
          .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
      }
      .foregroundColor(palette.metaColor)

      Spacer(minLength: 0)
    } menu: {
      collectionContextMenu
    }
    .sheet(isPresented: $showEditSheet, onDismiss: onChanged) {
      CollectionEditSheet(collection: item.collection)
    }
  }

  private func togglePinned() {
    let nextPinned = !item.isPinned
    Task {
      do {
        let database = try await DatabaseOperator.database()
        await database.setCollectionPinned(
          collectionId: item.collectionId,
          instanceId: item.instanceId,
          isPinned: nextPinned
        )
        onChanged()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
