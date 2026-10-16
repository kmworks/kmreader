//
// EpubColumnCount.swift
//
//

import Foundation

nonisolated enum EpubColumnCount: String, CaseIterable, Identifiable, Sendable {
  case auto
  case one
  case two

  var id: String { rawValue }

  var label: String {
    switch self {
    case .auto:
      return String(localized: "epub.columnCount.auto")
    case .one:
      return String(localized: "epub.columnCount.one")
    case .two:
      return String(localized: "epub.columnCount.two")
    }
  }

  var readiumValue: String? {
    switch self {
    case .auto:
      return nil
    case .one:
      return "1"
    case .two:
      return "2"
    }
  }
}
