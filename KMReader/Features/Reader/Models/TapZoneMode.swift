//
// TapZoneMode.swift
//
//

import SwiftUI

enum TapZoneMode: String, CaseIterable, Hashable, Sendable {
  case none = "none"
  case defaultLayout = "default"
  case edge = "edge"
  case kindle = "kindle"
  case lShape = "lShape"
  case tSplit = "tSplit"

  var displayName: String {
    switch self {
    case .none: return String(localized: "reader.tapZoneMode.none")
    case .defaultLayout: return String(localized: "reader.tapZoneMode.default")
    case .edge: return String(localized: "reader.tapZoneMode.edge")
    case .kindle: return String(localized: "reader.tapZoneMode.kindle")
    case .lShape: return String(localized: "reader.tapZoneMode.lShape")
    case .tSplit: return String(localized: "reader.tapZoneMode.tSplit")
    }
  }

  var isDisabled: Bool {
    self == .none
  }
}
