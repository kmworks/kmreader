//
// EpubFlowStyle.swift
//
//

import Foundation

nonisolated enum EpubFlowStyle: String, CaseIterable, Identifiable, Sendable {
  case paged = "paged"
  case scrolled = "scrolled"

  var id: String { rawValue }

  var isPaged: Bool {
    self == .paged
  }

  var displayName: String {
    switch self {
    case .paged:
      return String(localized: "epub.flow.paged")
    case .scrolled:
      return String(localized: "epub.flow.scrolled")
    }
  }
}
