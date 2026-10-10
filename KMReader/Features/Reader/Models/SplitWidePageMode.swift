//
// SplitWidePageMode.swift
//
//

import Foundation

enum SplitWidePageMode: String, CaseIterable, Hashable, Sendable {
  case none = "none"
  case auto = "auto"
  case ltr = "ltr"
  case rtl = "rtl"
  case scroll = "scroll"

  var displayName: String {
    switch self {
    case .none:
      return String(localized: "reader.tapZoneMode.none")
    case .auto:
      return String(localized: "reader.tapZoneMode.auto")
    case .ltr:
      return String(localized: "reading_direction.ltr", defaultValue: "Left to Right")
    case .rtl:
      return String(localized: "reading_direction.rtl", defaultValue: "Right to Left")
    case .scroll:
      return String(localized: "reader.splitWidePage.scroll", defaultValue: "Scroll")
    }
  }

  var icon: String {
    switch self {
    case .none:
      return "rectangle"
    case .auto:
      return "sparkles"
    case .ltr:
      return "rectangle.trailinghalf.inset.filled.arrow.trailing"
    case .rtl:
      return "rectangle.leadinghalf.inset.filled.arrow.leading"
    case .scroll:
      return "arrow.left.and.right.square"
    }
  }

  var isEnabled: Bool {
    self != .none
  }

  func effectiveReadingDirection(for readingDirection: ReadingDirection) -> ReadingDirection {
    switch self {
    case .none:
      return readingDirection
    case .auto:
      return readingDirection
    case .ltr:
      return .ltr
    case .rtl:
      return .rtl
    case .scroll:
      return readingDirection
    }
  }
}
