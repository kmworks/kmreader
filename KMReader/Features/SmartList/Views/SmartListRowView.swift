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
    .sheet(isPresented: $showEditSheet) {
      SmartListEditSheet(mode: .edit(smartList))
    }
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
