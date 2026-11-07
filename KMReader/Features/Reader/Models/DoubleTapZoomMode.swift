//
// DoubleTapZoomMode.swift
//
//

import Foundation

enum DoubleTapZoomMode: CaseIterable, Identifiable, RawRepresentable, Sendable {
  typealias RawValue = String

  case enabled
  case disabled

  nonisolated static let allCases: [DoubleTapZoomMode] = [.enabled, .disabled]

  nonisolated init?(rawValue: String) {
    switch rawValue {
    case "enabled", "fast", "slow":
      self = .enabled
    case "disabled":
      self = .disabled
    default:
      return nil
    }
  }

  nonisolated var rawValue: String {
    switch self {
    case .enabled: return "enabled"
    case .disabled: return "disabled"
    }
  }

  nonisolated var id: String { rawValue }

  nonisolated var isEnabled: Bool {
    self != .disabled
  }

  nonisolated var displayName: String {
    switch self {
    case .enabled: return String(localized: "Zoom")
    case .disabled: return String(localized: "Off")
    }
  }

  nonisolated var icon: String {
    switch self {
    case .enabled: return "magnifyingglass"
    case .disabled: return "hand.tap"
    }
  }
}
