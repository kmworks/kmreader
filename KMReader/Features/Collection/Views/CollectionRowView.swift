//
// CollectionRowView.swift
//
//

import SwiftUI

struct CollectionRowView: View {
  let item: CollectionDisplayItem
  var onMutationCompleted: (() -> Void)? = nil
  let onDeleteRequested: () -> Void

  @State private var showEditSheet = false

  var body: some View {
    HStack(spacing: 12) {
      NavigationLink(
        value: NavDestination.collectionDetail(collectionId: item.collectionId)
      ) {
        ThumbnailImage(id: item.collectionId, type: .collection, width: 60)
      }
      .adaptiveButtonStyle(.plain)

      VStack(alignment: .leading, spacing: 6) {
        NavigationLink(
          value: NavDestination.collectionDetail(collectionId: item.collectionId)
        ) {
          HStack(spacing: 6) {
            Text(item.name)
              .font(.callout)
              .lineLimit(2)
            if item.isPinned {
              Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }.adaptiveButtonStyle(.plain)

        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(item.seriesCount) series")
              .font(.footnote)
              .foregroundColor(.secondary)

            Text(item.lastModifiedDate.formatted(date: .abbreviated, time: .omitted))
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          EllipsisMenuButton {
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
            .id(item.collectionId)
          }
        }
      }
    }
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
