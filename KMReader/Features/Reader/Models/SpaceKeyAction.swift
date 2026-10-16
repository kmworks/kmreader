//
// SpaceKeyAction.swift
//
//

import Foundation

enum SpaceKeyAction: String, CaseIterable, Identifiable, Sendable {
  case toggleControls = "toggleControls"
  case nextPage = "nextPage"

  nonisolated var id: String { rawValue }

  var displayName: String {
    switch self {
    case .toggleControls: return String(localized: "reader.spaceKeyAction.toggleControls")
    case .nextPage: return String(localized: "reader.spaceKeyAction.nextPage")
    }
  }
}
