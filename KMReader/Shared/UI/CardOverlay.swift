//
// CardOverlay.swift
//
//

import SwiftUI

struct UnreadCountBadge: View {
  let count: Int
  let size: CGFloat
  /// Must match the cover's corner radius so the badge arc overlaps the
  /// cover clip exactly; a different radius or corner style lets the cover
  /// bleed through at the top-right corner.
  let cornerRadius: CGFloat

  #if os(tvOS)
    static let defaultSize: CGFloat = 24
  #else
    static let defaultSize: CGFloat = 12
  #endif

  @State private var measuredHeight: CGFloat = 0
  @State private var bounceScale: CGFloat = 1

  init(count: Int, size: CGFloat = defaultSize, cornerRadius: CGFloat = 8) {
    self.count = count
    self.size = size
    self.cornerRadius = cornerRadius
  }

  private var badgeFont: Font {
    .system(size: size, weight: .semibold, design: .rounded)
  }

  /// Width is measured with the last digit replaced by the wide digit "8", so
  /// a change between same-length counts never resizes the badge.
  private var sizingText: String {
    String(String(max(count, 0)).dropLast()) + "8"
  }

  var body: some View {
    Text(sizingText)
      .font(badgeFont)
      .opacity(0)
      .accessibilityHidden(true)
      .overlay {
        Text("\(count)")
          .font(badgeFont)
          .contentTransition(.numericText())
      }
      .foregroundStyle(.white)
      .padding(.horizontal, size * 0.6)
      .padding(.vertical, size * 0.35)
      .accessibilityLabel(
        Text(String.localizedStringWithFormat(String(localized: "%lld unread"), count))
      )
      .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
        measuredHeight = height
      }
      .frame(minWidth: measuredHeight)
      .background(
        UnevenRoundedRectangle(
          bottomLeadingRadius: size * 0.65,
          topTrailingRadius: cornerRadius,
          style: .circular
        )
        .fill(Color(white: 0.12))
      )
      .scaleEffect(bounceScale)
      .animation(.appCurve(0.2), value: count)
      .onChange(of: count) { oldValue, newValue in
        guard newValue > oldValue else { return }
        withAnimation(.appCurve(0.12), completionCriteria: .removed) {
          bounceScale = 1.2
        } completion: {
          withAnimation(.appCurve(0.12)) {
            bounceScale = 1
          }
        }
      }
  }
}

struct CompletedIndicator: View {
  let size: CGFloat
  /// See UnreadCountBadge.cornerRadius.
  let cornerRadius: CGFloat

  #if os(tvOS)
    static let defaultSize: CGFloat = 24
  #else
    static let defaultSize: CGFloat = 12
  #endif

  init(size: CGFloat = defaultSize, cornerRadius: CGFloat = 8) {
    self.size = size
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    // Glyph matches the count digit's visual weight; glyph + padding keep the
    // badge's total height at UnreadCountBadge's ~1.9×size.
    Image(systemName: "checkmark")
      .font(.system(size: size * 0.85, weight: .bold))
      .foregroundStyle(.white)
      .padding(size * 0.6)
      .background(
        UnevenRoundedRectangle(
          bottomLeadingRadius: size * 0.65,
          topTrailingRadius: cornerRadius,
          style: .circular
        )
        .fill(Color(white: 0.12))
      )
      .accessibilityLabel(Text("Completed"))
  }
}

#Preview {
  VStack {
    HStack {
      ZStack(alignment: .topTrailing) {
        Rectangle()
          .fill(Color.gray.opacity(0.3))
          .aspectRatio(0.7, contentMode: .fit)
          .cornerRadius(8)
          .overlay(
            Image(systemName: "photo")
              .foregroundColor(.gray)
          )

        UnreadCountBadge(count: 291)
      }.frame(height: 160)

      ZStack(alignment: .topTrailing) {
        Rectangle()
          .fill(Color.gray.opacity(0.3))
          .aspectRatio(0.7, contentMode: .fit)
          .cornerRadius(8)
          .overlay(
            Image(systemName: "photo")
              .foregroundColor(.gray)
          )

        CompletedIndicator()
      }.frame(height: 160)
    }
  }
  .padding()
}
