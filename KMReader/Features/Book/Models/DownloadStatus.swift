//
// DownloadStatus.swift
//
//

import Foundation
import SwiftUI

/// Status of an offline book download (persisted in the local database).
/// Note: Downloading progress is tracked separately in OfflineManager.
nonisolated enum DownloadStatus: Equatable, Sendable {
  case notDownloaded
  case pending
  case downloaded
  case failed(error: String)

  // MARK: - Display

  var displayLabel: String {
    switch self {
    case .notDownloaded:
      return String(localized: "status.not_downloaded")
    case .pending:
      return String(localized: "status.pending")
    case .downloaded:
      return String(localized: "status.downloaded")
    case .failed(let error):
      return error
    }
  }

  var displayIcon: String? {
    switch self {
    case .notDownloaded:
      return nil
    case .pending:
      return "arrow.clockwise"
    case .downloaded:
      return "checkmark.icloud.fill"
    case .failed:
      return "exclamationmark.circle.fill"
    }
  }

  /// Status-icon color: failures stand out in red, everything else stays quiet.
  var displayColor: Color {
    switch self {
    case .failed:
      return .red
    case .notDownloaded, .pending, .downloaded:
      return .secondary
    }
  }

  /// Red only on failure; tinted/overlay cards keep their palette color otherwise.
  var failureColor: Color? {
    if case .failed = self { return .red }
    return nil
  }

  // MARK: - Menu Display

  /// Label for context menu actions.
  var menuLabel: String {
    switch self {
    case .downloaded:
      return String(localized: "Remove Offline")
    case .pending:
      return String(localized: "Cancel Download")
    case .notDownloaded:
      return String(localized: "Make Offline")
    case .failed:
      return String(localized: "Retry Download")
    }
  }

  /// Notification message after toggling away from this status.
  var toggledNotification: String {
    switch self {
    case .downloaded:
      return String(localized: "notification.book.offlineRemoved", defaultValue: "Removed from offline")
    case .pending:
      return String(localized: "notification.book.downloadCancelled", defaultValue: "Download cancelled")
    case .notDownloaded, .failed:
      return String(localized: "notification.book.downloadQueued", defaultValue: "Download queued")
    }
  }

  /// Icon for context menu and toolbar actions.
  var menuIcon: String {
    switch self {
    case .downloaded:
      return "trash"
    case .pending:
      return "xmark.circle"
    case .notDownloaded, .failed:
      return "icloud.and.arrow.down"
    }
  }

  /// Color for the status icon.
  var menuColor: Color {
    switch self {
    case .downloaded, .pending:
      return .red
    case .notDownloaded, .failed:
      return .primary
    }
  }

  var isDownloaded: Bool {
    self == .downloaded
  }

  var isPending: Bool {
    self == .pending
  }
}
