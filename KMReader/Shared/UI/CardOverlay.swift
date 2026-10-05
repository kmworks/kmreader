//
// CardOverlay.swift
//
//

import SwiftUI

/// Shared corner-badge shell: a hidden sizing text anchors the badge's height
/// and a stable same-length width, the content overlays it, and the slab
/// matches the cover's top-right corner.
private struct CornerBadgeShell<Content: View>: View {
  let sizingText: String
  let size: CGFloat
  /// Must match the cover's corner radius so the badge arc overlaps the
  /// cover clip exactly; a different radius or corner style lets the cover
  /// bleed through at the top-right corner.
  let cornerRadius: CGFloat
  @ViewBuilder let content: () -> Content

  @State private var measuredHeight: CGFloat = 0

  private var badgeFont: Font {
    .system(size: size, weight: .semibold, design: .rounded)
  }

  var body: some View {
    Text(sizingText)
      .font(badgeFont)
      .opacity(0)
      .accessibilityHidden(true)
      .overlay { content() }
      .foregroundStyle(.white)
      .padding(.horizontal, size * 0.6)
      .padding(.vertical, size * 0.35)
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
  }
}

struct UnreadCountBadge: View {
  let count: Int
  let size: CGFloat
  /// See CornerBadgeShell.cornerRadius.
  let cornerRadius: CGFloat

  #if os(tvOS)
    static let defaultSize: CGFloat = 24
  #else
    static let defaultSize: CGFloat = 12
  #endif

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
    CornerBadgeShell(sizingText: sizingText, size: size, cornerRadius: cornerRadius) {
      Text("\(count)")
        .font(badgeFont)
        .contentTransition(.numericText())
        // "11" is wider than its "18" anchor in the rounded font; without a
        // free size the count truncates to an ellipsis.
        .fixedSize()
    }
    .accessibilityLabel(
      Text(String.localizedStringWithFormat(String(localized: "%lld unread"), count))
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
  /// See CornerBadgeShell.cornerRadius.
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
    CornerBadgeShell(sizingText: "8", size: size, cornerRadius: cornerRadius) {
      Image(systemName: "checkmark")
        .font(.system(size: size * 0.85, weight: .bold))
    }
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
