//
// ReaderImageUpscalingMode.swift
//
//

import Foundation

enum ReaderImageUpscalingMode: String, CaseIterable, Hashable, Sendable {
  case disabled
  case auto

  var displayName: String {
    switch self {
    case .disabled:
      return String(localized: "Disabled")
    case .auto:
      return String(localized: "Auto")
    }
  }
}
