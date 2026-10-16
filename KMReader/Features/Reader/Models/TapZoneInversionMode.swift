//
// TapZoneInversionMode.swift
//
//

import SwiftUI

enum TapZoneInversionMode: String, CaseIterable, Hashable, Sendable {
  case normal = "normal"
  case auto = "auto"
  case inverted = "inverted"

  var displayName: String {
    switch self {
    case .normal: return String(localized: "reader.tapZoneInversionMode.normal")
    case .auto: return String(localized: "reader.tapZoneInversionMode.auto")
    case .inverted: return String(localized: "reader.tapZoneInversionMode.inverted")
    }
  }

  func isInverted(for readingDirection: ReadingDirection) -> Bool {
    switch self {
    case .normal:
      return false
    case .auto:
      return readingDirection == .rtl
    case .inverted:
      return true
    }
  }
}
