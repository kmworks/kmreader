//
// TriStateSelectionIcon.swift
//
//

import SwiftUI

extension TriStateSelection {
  /// The include/exclude glyphs are filled in every context — the fill is part
  /// of the state's identity, not a rendering variant.
  var iconName: String {
    switch self {
    case .off:
      return "circle"
    case .include:
      return "checkmark.circle.fill"
    case .exclude:
      return "xmark.circle.fill"
    }
  }

  var color: Color {
    switch self {
    case .off:
      return .secondary
    case .include:
      return .primary
    case .exclude:
      return .red
    }
  }
}
