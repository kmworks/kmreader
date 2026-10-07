//
// SmartListRowView.swift
//
//

import SwiftUI

struct SmartListRowView: View {
  let smartList: SmartList

  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false

  var body: some View {
    HStack(spacing: 12) {
      NavigationLink(value: NavDestination.smartListDetail(smartListId: smartList.id)) {
        ThumbnailImage(id: smartList.id, type: .smartList, width: 60)
      }
      .adaptiveButtonStyle(.plain)

      VStack(alignment: .leading, spacing: 6) {
        NavigationLink(value: NavDestination.smartListDetail(smartListId: smartList.id)) {
          Text(smartList.name)
            .font(.callout)
            .lineLimit(2)
        }.adaptiveButtonStyle(.plain)

        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(smartList.targetDisplayName)
              .font(.footnote)
              .foregroundColor(.secondary)

            Text(smartList.lastModifiedDate.formatted(date: .abbreviated, time: .omitted))
              .font(.caption)
              .foregroundColor(.secondary)

            if !smartList.summary.isEmpty {
              Text(smartList.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }

          Spacer()

          EllipsisMenuButton {
            SmartListContextMenu(
              smartList: smartList,
              onEditRequested: {
                showEditSheet = true
              },
              onDeleteRequested: {
                showDeleteConfirmation = true
              }
            )
            .id(smartList.id)
          }
        }
      }
    }
    .smartListItemActions(
      smartList: smartList,
      showEditSheet: $showEditSheet,
      showDeleteConfirmation: $showDeleteConfirmation
    )
  }
}
