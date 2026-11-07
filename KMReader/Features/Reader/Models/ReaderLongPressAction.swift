//
// ReaderLongPressAction.swift
//
//

import Foundation

enum ReaderLongPressAction: String, CaseIterable, Identifiable, Sendable {
  case panelMode
  case contextMenu
  case disabled

  nonisolated var id: String { rawValue }

  nonisolated var displayName: String {
    switch self {
    case .panelMode: return String(localized: "Panel Mode")
    case .contextMenu: return String(localized: "Image Context Menu")
    case .disabled: return String(localized: "Off")
    }
  }
}
