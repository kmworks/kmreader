//
// ReaderLongPressAction.swift
//
//

import Foundation

enum ReaderLongPressAction: String, CaseIterable, Identifiable, Sendable {
  case contextMenu
  case disabled

  nonisolated var id: String { rawValue }

  nonisolated var displayName: String {
    switch self {
    case .contextMenu: return String(localized: "Image Context Menu")
    case .disabled: return String(localized: "Off")
    }
  }

  nonisolated var icon: String {
    switch self {
    case .contextMenu: return "photo"
    case .disabled: return AppIcon.gestureDisabled
    }
  }
}
