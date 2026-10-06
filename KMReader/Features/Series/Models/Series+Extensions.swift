//
// Series+Extensions.swift
//
//

import SwiftUI

extension Series {
  private var normalizedStatus: String {
    (metadata.status ?? "Unknown").uppercased()
  }

  var statusDisplayName: LocalizedStringKey {
    switch normalizedStatus {
    case "ONGOING": return "Ongoing"
    case "ENDED": return "Ended"
    case "ABANDONED": return "Abandoned"
    case "HIATUS": return "Hiatus"
    default: return LocalizedStringKey((metadata.status ?? "Unknown").capitalized)
    }
  }

  var statusColor: Color {
    switch normalizedStatus {
    case "ONGOING": return .blue
    case "ENDED": return .green
    case "ABANDONED": return .red
    case "HIATUS": return .orange
    default: return .secondary
    }
  }

  var statusIcon: String {
    SeriesStatus.fromAPIValue(metadata.status)?.icon ?? "questionmark.circle"
  }

  var readStatus: ReadStatus {
    ReadStatus.fromSeriesCounts(
      booksCount: booksCount,
      booksReadCount: booksReadCount,
      booksInProgressCount: booksInProgressCount
    )
  }

  var readStatusDisplayName: String {
    readStatus.displayName
  }

  var readStatusIcon: String {
    readStatus.icon
  }

  var lastUpdatedDisplay: String {
    lastModified.formatted(date: .abbreviated, time: .omitted)
  }

  var readStatusColor: Color {
    switch readStatus {
    case .read: return .green
    case .inProgress: return .blue
    case .unread: return .secondary
    }
  }
}
