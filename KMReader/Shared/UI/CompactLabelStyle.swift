//
// CompactLabelStyle.swift
//
//

import SwiftUI

/// Tight icon+title row for dense card text lines: a default Label renders the
/// symbol at the full em height, which looms over caption-sized text.
struct CompactLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 2) {
      configuration.icon
        .imageScale(.small)
      configuration.title
    }
  }
}

extension LabelStyle where Self == CompactLabelStyle {
  static var compact: CompactLabelStyle {
    CompactLabelStyle()
  }
}
