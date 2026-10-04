//
// LibrarySelectionIndicator.swift
//
//

import SwiftUI

/// Selection checkmark for library rows: a single circle in multi-select, a
/// radio circle in single-select.
struct LibrarySelectionIndicator: View {
  let isSelected: Bool
  var isSingleSelectionMode: Bool = false

  private var indicatorName: String {
    if isSingleSelectionMode {
      return isSelected ? "largecircle.fill.circle" : "circle"
    }
    return isSelected ? "checkmark.circle.fill" : "circle"
  }

  var body: some View {
    Image(systemName: indicatorName)
      .foregroundStyle(isSelected ? Color.primary : .secondary)
      .font(.title3)
      .animation(.appCurve(), value: isSelected)
  }
}
