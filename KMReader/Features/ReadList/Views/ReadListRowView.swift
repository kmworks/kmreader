//
// ReadListRowView.swift
//
//

import SwiftUI

struct ReadListRowView: View {
  let item: ReadListDisplayItem
  var onMutationCompleted: (() -> Void)? = nil
  let onDeleteRequested: () -> Void

  @State private var showEditSheet = false

  var body: some View {
    HStack(spacing: 12) {
      NavigationLink(value: NavDestination.readListDetail(readListId: item.readListId)) {
        ThumbnailImage(id: item.readListId, type: .readlist, width: 60)
      }
      .adaptiveButtonStyle(.plain)

      VStack(alignment: .leading, spacing: 6) {
        NavigationLink(value: NavDestination.readListDetail(readListId: item.readListId)) {
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
            Text("\(item.bookCount) books")
              .font(.footnote)
              .foregroundColor(.secondary)

            Text(item.lastModifiedDate.formatted(date: .abbreviated, time: .omitted))
              .font(.caption)
              .foregroundColor(.secondary)

            if !item.summary.isEmpty {
              Text(item.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }

          Spacer()

          EllipsisMenuButton {
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
            .id(item.readListId)
          }
        }
      }
    }
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
