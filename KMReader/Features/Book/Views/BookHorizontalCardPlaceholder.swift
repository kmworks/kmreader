//
// BookHorizontalCardPlaceholder.swift
//
//

import SwiftUI

/// Placeholder skeleton matching BookHorizontalCardView while data is loading
struct BookHorizontalCardPlaceholder: View {
  var coverWidth: CGFloat = 45

  private let cornerRadius: CGFloat = 8

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.gray.opacity(0.2))
        .shimmer(cornerRadius: cornerRadius)
        .aspectRatio(CoverAspectRatio.widthToHeight, contentMode: .fit)
        .frame(width: coverWidth)

      VStack(alignment: .leading, spacing: 4) {
        placeholderLine(
          size: LayoutConfig.horizontalCardFontSize,
          text: "Book Title", widthScale: 0.8, opacity: 0.2)
        placeholderLine(
          size: LayoutConfig.horizontalCardSeriesFontSize,
          text: "Series Title", widthScale: 0.45, opacity: 0.18)
        placeholderLine(
          size: LayoutConfig.horizontalCardMetaFontSize,
          text: "40% • 120 pages", widthScale: 0.55, opacity: 0.15)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.cardBackground)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
  }

  private func placeholderLine(
    size: CGFloat,
    text: String,
    widthScale: CGFloat,
    opacity: Double
  ) -> some View {
    Text(text)
      .font(.system(size: size))
      .foregroundColor(.clear)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color.gray.opacity(opacity))
          .shimmer(cornerRadius: cornerRadius)
          .frame(maxWidth: .infinity, alignment: .leading)
          .scaleEffect(x: widthScale, anchor: .leading)
      }
      .accessibilityHidden(true)
  }
}
