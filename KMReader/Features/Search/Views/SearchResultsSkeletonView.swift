//
// SearchResultsSkeletonView.swift
//
//

import SwiftUI

/// Loading placeholder for the search overview: two shimmering preview strips.
struct SearchResultsSkeletonView: View {
  private let cornerRadius: CGFloat = 8

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<2, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 0) {
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.2))
            .shimmer(cornerRadius: cornerRadius)
            .frame(width: 160, height: 22)
            .padding(.horizontal)
            .padding(.top, LayoutConfig.dashboardSectionTopPadding)

          HStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
            ForEach(0..<6, id: \.self) { _ in
              CardPlaceholder(
                layout: .grid,
                kind: .series,
                cardWidth: LayoutConfig.gridCardWidth
              )
              .frame(width: LayoutConfig.gridCardWidth)
            }
          }
          .padding(.horizontal)
          .padding(.top, LayoutConfig.dashboardSectionHeaderSpacing)
          .padding(.bottom, LayoutConfig.dashboardSectionBottomPadding(gradientBackground: false))
        }
      }
    }
    .accessibilityHidden(true)
  }
}
