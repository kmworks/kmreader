//
// SeriesBookCountView.swift
//
//

import SwiftUI

/// Book count and aggregate read status line shown inside the series detail
/// action card.
struct SeriesBookCountView: View {
  let series: Series

  @Environment(\.detailHeroCentered) private var heroCentered

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: heroCentered ? .center : .leading)
  }

  @ViewBuilder
  private var content: some View {
    if series.deleted {
      Label("Unavailable", systemImage: "exclamationmark.circle")
        .font(.subheadline)
        .foregroundStyle(.red)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if let totalBookCount = series.metadata.totalBookCount {
          Text("\(series.booksCount) / \(totalBookCount) books")
            .font(.subheadline.weight(.semibold))
        } else {
          Text("\(series.booksCount) books")
            .font(.subheadline.weight(.semibold))
        }

        if series.booksUnreadCount > 0 && series.booksUnreadCount < series.booksCount {
          Label("\(series.booksUnreadCount) unread", systemImage: ReadStatus.unread.icon)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if series.booksInProgressCount > 0 {
          Label("\(series.booksInProgressCount) in progress", systemImage: ReadStatus.inProgress.icon)
            .font(.caption)
            .foregroundStyle(.orange)
        } else if series.booksUnreadCount == 0 && series.booksCount > 0 {
          Label("All read", systemImage: ReadStatus.read.icon)
            .symbolVariant(.fill)
            .font(.caption)
            .foregroundStyle(.green)
        } else if series.booksCount > 0 {
          Label("Unread", systemImage: ReadStatus.unread.icon)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
