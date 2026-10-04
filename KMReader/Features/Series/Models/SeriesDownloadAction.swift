//
// SeriesDownloadAction.swift
//
//

import Foundation

enum SeriesDownloadAction: String, Identifiable, CaseIterable {
  case download
  case downloadUnread
  case removeRead
  case remove
  case cancel

  var id: String { rawValue }

  func label(for status: SeriesDownloadStatus) -> String {
    switch self {
    case .download:
      return String(localized: "Download All")
    case .downloadUnread:
      return String(localized: "Download Unread")
    case .removeRead:
      return String(localized: "Remove Read")
    case .remove:
      return String(localized: "Remove All")
    case .cancel:
      return String(localized: "Cancel Download")
    }
  }

  func icon(for status: SeriesDownloadStatus) -> String {
    switch self {
    case .download:
      return "icloud.and.arrow.down"
    case .downloadUnread:
      return "book.circle"
    case .removeRead:
      return "trash.circle"
    case .remove:
      return "trash"
    case .cancel:
      return "xmark.circle"
    }
  }

  var isDestructive: Bool {
    switch self {
    case .remove, .removeRead, .cancel:
      return true
    default:
      return false
    }
  }

  var requiresConfirmation: Bool {
    switch self {
    case .download, .downloadUnread, .removeRead, .remove:
      return true
    case .cancel:
      return false
    }
  }

  func confirmationMessage(for status: SeriesDownloadStatus) -> String {
    switch self {
    case .download:
      return String(localized: "confirm.download_all_books")
    case .downloadUnread:
      return String(localized: "confirm.download_unread_books")
    case .removeRead:
      return String(localized: "confirm.remove_read_offline_books")
    case .remove:
      return String(localized: "confirm.remove_all_offline_books")
    case .cancel:
      return ""
    }
  }

  static func availableActions(for status: SeriesDownloadStatus) -> [SeriesDownloadAction] {
    switch status {
    case .notDownloaded:
      return [.download, .downloadUnread]
    case .partiallyDownloaded, .failed:
      return [.download, .downloadUnread, .removeRead, .remove]
    case .downloaded:
      return [.removeRead, .remove]
    case .pending:
      return [.cancel]
    }
  }

  static func availableReadListActions(for status: SeriesDownloadStatus) -> [SeriesDownloadAction] {
    switch status {
    case .pending:
      return [.cancel, .remove]
    default:
      return availableActions(for: status)
    }
  }
}
