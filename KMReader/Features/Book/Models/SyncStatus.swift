import SwiftUI

enum SyncStatus {
  case paused
  case downloading
  case syncing
  case idle

  var label: String {
    switch self {
    case .paused: return String(localized: "Paused")
    case .downloading: return String(localized: "Downloading")
    case .syncing: return String(localized: "Syncing")
    case .idle: return String(localized: "Idle")
    }
  }

  var icon: String {
    switch self {
    case .paused: return "pause.circle.fill"
    case .downloading: return "arrow.down.circle.fill"
    case .syncing: return "arrow.clockwise.circle.fill"
    case .idle: return "checkmark.circle.fill"
    }
  }
}
