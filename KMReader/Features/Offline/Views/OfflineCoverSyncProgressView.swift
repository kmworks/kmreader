//
// OfflineCoverSyncProgressView.swift
//
//

import SwiftUI

struct OfflineCoverSyncProgressView: View {
  let progress: OfflineCoverSyncProgress

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ProgressView(value: progress.progressFraction)
        .animation(.appCurve(0.2), value: progress.progressFraction)
      HStack(spacing: 8) {
        Text(
          String(
            localized:
              "offline.coverSync.progressChecked \(progress.checkedCount) \(progress.totalCount)"
          )
        )
        .contentTransition(.numericText())
        .animation(.appCurve(), value: progress.checkedCount)
        .animation(.appCurve(), value: progress.totalCount)
        Text(String(localized: "offline.coverSync.progressSynced \(progress.storedCount)"))
          .contentTransition(.numericText())
          .animation(.appCurve(), value: progress.storedCount)
        if progress.failedCount > 0 {
          Text(String(localized: "offline.coverSync.progressFailed \(progress.failedCount)"))
            .contentTransition(.numericText())
            .animation(.appCurve(), value: progress.failedCount)
        }
      }
      .lineLimit(1)
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }
}
