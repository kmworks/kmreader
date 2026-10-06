//
// SeriesDownloadStatus.swift
//
//

import Foundation
import SwiftUI

/// Custom status for series download progress.
nonisolated enum SeriesDownloadStatus: Equatable, Sendable {
  case notDownloaded
  case partiallyDownloaded(downloaded: Int, total: Int)
  case downloaded
  case pending(downloaded: Int, pending: Int, total: Int)
  case failed

  var label: String {
    switch self {
    case .notDownloaded:
      return String(localized: "status.not_downloaded")
    case .partiallyDownloaded(let downloaded, let total):
      return String(localized: "status.partially_downloaded \(downloaded)/\(total)")
    case .downloaded:
      return String(localized: "status.downloaded")
    case .pending(let downloaded, let pending, let total):
      return String(localized: "status.pending \(downloaded)+\(pending)/\(total)")
    case .failed:
      return String(localized: "Failed")
    }
  }

  var icon: String? {
    switch self {
    case .notDownloaded:
      return nil
    case .partiallyDownloaded:
      return AppIcon.downloadPartial
    case .downloaded:
      return AppIcon.downloaded
    case .pending:
      return "arrow.clockwise"
    case .failed:
      return AppIcon.downloadFailed
    }
  }

  /// Status-icon color: failures stand out in red, everything else stays quiet.
  var displayColor: Color {
    switch self {
    case .failed:
      return .red
    case .notDownloaded, .partiallyDownloaded, .downloaded, .pending:
      return .secondary
    }
  }

  /// Red only on failure; tinted/overlay cards keep their palette color otherwise.
  var failureColor: Color? {
    self == .failed ? .red : nil
  }

  var isDownloaded: Bool {
    if case .downloaded = self { return true }
    return false
  }

  var isPending: Bool {
    if case .pending = self { return true }
    return false
  }

}
