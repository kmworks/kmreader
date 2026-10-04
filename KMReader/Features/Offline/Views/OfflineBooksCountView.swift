//
// OfflineBooksCountView.swift
//
//

import SwiftUI

struct OfflineBooksCountView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var downloadedCount: Int = 0
  @State private var progressTracker = DownloadProgressTracker.shared

  var body: some View {
    Group {
      if downloadedCount > 0 {
        Text("\(downloadedCount)")
          .font(.caption2)
          .fontWeight(.semibold)
          .monospacedDigit()
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(LayoutConfig.neutralFillColor, in: Capsule())
          .foregroundColor(.secondary)
      } else {
        Text("")
      }
    }
    .task(id: current.instanceId) {
      await loadCount()
    }
    .onChange(of: progressTracker.queueUpdateToken) { _, _ in
      Task { await loadCount() }
    }
  }

  @MainActor
  private func loadCount() async {
    let instanceId = current.instanceId
    guard !instanceId.isEmpty else {
      withAnimation {
        downloadedCount = 0
      }
      return
    }
    let count =
      (try? await DatabaseOperator.database().fetchDownloadedBooksCount(instanceId: instanceId))
      ?? 0
    withAnimation {
      downloadedCount = count
    }
  }
}
