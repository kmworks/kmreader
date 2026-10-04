//
// DetailActionCard.swift
//
//

import SwiftUI

/// Grouped container for a detail page's reading state and primary
/// actions, giving the page a single visual focal point.
struct DetailActionCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      content
    }
    .padding(12)
    .background(
      LayoutConfig.neutralFillColor,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
  }
}
