//
// BrowseLayoutMode.swift
//
//

import Foundation
import SwiftUI

enum BrowseLayoutMode: String, CaseIterable, Identifiable, Sendable {
  case list
  case grid
  case largeGrid

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .list: return String(localized: "browse.layout.list")
    case .grid: return String(localized: "browse.layout.mediumGrid")
    case .largeGrid: return String(localized: "browse.layout.largeGrid")
    }
  }

  var iconName: String {
    switch self {
    case .list: return "list.bullet"
    case .grid: return "rectangle.grid.3x2"
    case .largeGrid: return "square.grid.2x2"
    }
  }

  /// Nominal card width for grid-style layouts; drives the adaptive column
  /// minimum and the card text/badge scaling. Unused by row layout.
  var cardWidth: CGFloat {
    switch self {
    case .largeGrid: return LayoutConfig.largeGridCardWidth
    case .list, .grid: return LayoutConfig.gridCardWidth
    }
  }
}
