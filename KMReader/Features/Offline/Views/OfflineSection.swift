//
// OfflineSection.swift
//
//

import SwiftUI

enum OfflineSection: String, CaseIterable {
  case tasks
  case books

  var icon: String {
    switch self {
    case .tasks:
      return "arrow.down.circle"
    case .books:
      return ContentIcon.library
    }
  }

  var color: Color {
    switch self {
    case .tasks:
      return .blue
    case .books:
      return .green
    }
  }

  var title: String {
    switch self {
    case .tasks:
      return String(localized: "Download Tasks")
    case .books:
      return String(localized: "Downloaded Books")
    }
  }
}
