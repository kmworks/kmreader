//
// LibrarySelectionIndicator.swift
//
//

import SwiftUI

/// Selection checkmark for library rows.
struct LibrarySelectionIndicator: View {
  let isSelected: Bool

  var body: some View {
    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
      .foregroundStyle(isSelected ? Color.primary : .secondary)
      .font(.title3)
      .animation(.appCurve(), value: isSelected)
  }
}
