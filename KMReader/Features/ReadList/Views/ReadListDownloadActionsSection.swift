//
// ReadListDownloadActionsSection.swift
//
//

import SwiftUI

struct ReadListDownloadActionsSection: View {
  let readListId: String
  let status: SeriesDownloadStatus
  let policy: OfflinePolicy
  let offlinePolicyLimit: Int
  var onMutationCompleted: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @Environment(\.detailHeroCentered) private var heroCentered

  private var offlineActions: ReadListOfflineActions {
    ReadListOfflineActions(
      readListId: readListId,
      instanceId: current.instanceId,
      onMutationCompleted: onMutationCompleted
    )
  }

  var body: some View {
    HStack(spacing: 12) {
      Menu {
        ReadListDownloadActionMenuItems(status: status, actions: offlineActions)
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "icloud.and.arrow.down")
            .font(.caption2)
          Text(String(localized: "Download"))
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
        }
      }
      .adaptiveButtonStyle(.bordered)
      .optimizedControlSize()

      Menu {
        ReadListOfflinePolicyMenuItems(
          policy: policy,
          offlinePolicyLimit: offlinePolicyLimit,
          actions: offlineActions
        )
      } label: {
        HStack(spacing: 4) {
          Image(systemName: policy.icon)
            .font(.caption2)
          Text(String(localized: "Offline Policy"))
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
        }
      }
      .adaptiveButtonStyle(.bordered)
      .optimizedControlSize()

      if !heroCentered {
        Spacer()
      }

      if let icon = status.icon {
        DownloadStatusIcon(systemName: icon, spinning: status.isPending)
          .font(.caption)
          .accessibilityLabel(status.label)
      }
    }
    .frame(maxWidth: .infinity, alignment: heroCentered ? .center : .leading)
    .padding(.vertical, 4)
    .animation(.appCurve(), value: status)
  }
}
