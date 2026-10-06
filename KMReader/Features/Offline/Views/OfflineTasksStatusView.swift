//
// OfflineTasksStatusView.swift
//
//

import SwiftUI

struct OfflineTasksStatusView: View {
  @AppStorage("offlinePaused") private var offlinePaused: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var summary: DownloadQueueSummary = .empty
  @State private var progressTracker = DownloadProgressTracker.shared

  var body: some View {
    HStack(spacing: 6) {
      if offlinePaused {
        statusBadge(
          title: SyncStatus.paused.label,
          systemImage: SyncStatus.paused.icon
        )
      } else if summary.isEmpty {
        statusBadge(
          title: SyncStatus.idle.label,
          systemImage: SyncStatus.idle.icon
        )
      } else {

        if summary.downloadingCount > 0 {
          statusBadge(
            title: "\(summary.downloadingCount)",
            systemImage: "arrow.down.circle.fill"
          )
        }
        if summary.pendingCount > 0 {
          statusBadge(
            title: "\(summary.pendingCount)",
            systemImage: "clock.fill"
          )
        }
        if summary.failedCount > 0 {
          statusBadge(
            title: "\(summary.failedCount)",
            systemImage: AppIcon.downloadFailed
          )
        }
      }
    }
    .task(id: current.instanceId) {
      await loadSummary()
    }
    .onChange(of: progressTracker.queueUpdateToken) { _, _ in
      Task { await loadSummary() }
    }
  }

  @ViewBuilder
  private func statusBadge(title: String, systemImage: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: systemImage)
        .font(.caption2)
      Text(title)
        .font(.caption2)
        .fontWeight(.semibold)
        .monospacedDigit()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(LayoutConfig.neutralFillColor, in: Capsule())
    .foregroundColor(.secondary)
  }

  @MainActor
  private func loadSummary() async {
    let instanceId = current.instanceId
    guard !instanceId.isEmpty else {
      withAnimation {
        summary = .empty
      }
      return
    }
    let newSummary =
      (try? await DatabaseOperator.database().fetchDownloadQueueSummary(
        instanceId: instanceId
      )) ?? .empty
    withAnimation {
      summary = newSummary
    }
  }
}
