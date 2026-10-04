//
// ReadListDownloadActionMenuItems.swift
//
//

import SwiftUI

/// Download action menu entries for a read list's download status, shared by
/// the context menu and the detail-page actions section.
struct ReadListDownloadActionMenuItems: View {
  let status: SeriesDownloadStatus
  let actions: ReadListOfflineActions

  var body: some View {
    ForEach(SeriesDownloadAction.availableReadListActions(for: status)) { action in
      actionMenuItem(action: action)
    }
  }

  @ViewBuilder
  private func actionMenuItem(action: SeriesDownloadAction) -> some View {
    switch action {
    case .downloadUnread:
      Menu {
        ForEach(ReadListOfflineActions.limitPresets, id: \.self) { value in
          Button {
            actions.downloadUnread(limit: value)
          } label: {
            Text(OfflinePolicy.limitTitle(value))
          }
        }
      } label: {
        Label(action.label(for: status), systemImage: action.icon(for: status))
      }
    default:
      Button(role: action.isDestructive ? .destructive : .none) {
        actions.perform(action)
      } label: {
        Label(action.label(for: status), systemImage: action.icon(for: status))
      }
    }
  }
}
