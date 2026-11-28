//
// SearchViewAllCard.swift
//
//

import SwiftUI

/// Trailing cover-sized card in a search preview strip when more matches
/// exist than the preview shows; opens the category's full results page.
struct SearchViewAllCard: View {
  let destination: NavDestination

  private let cornerRadius: CGFloat = 8

  var body: some View {
    NavigationLink(value: destination) {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(LayoutConfig.neutralFillColor)
        .aspectRatio(CoverAspectRatio.widthToHeight, contentMode: .fit)
        .overlay {
          VStack(spacing: 6) {
            Text(String(localized: "search.viewAll", defaultValue: "View All"))
              .font(.footnote.weight(.medium))
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
          }
          .foregroundStyle(.secondary)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    .adaptiveButtonStyle(.plain)
    .frame(width: LayoutConfig.gridCardWidth, alignment: .top)
  }
}
