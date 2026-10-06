//
// CardOverlay.swift
//
//

import SwiftUI

/// Slab behind corner badges, shaped to the cover's top-right corner.
private struct CornerBadgeSlab: View {
  let size: CGFloat
  /// Must match the cover's corner radius so the badge arc overlaps the cover
  /// clip exactly; a different radius lets the cover bleed through at the corner.
  let cornerRadius: CGFloat

  var body: some View {
    UnevenRoundedRectangle(
      bottomLeadingRadius: size * 0.65,
      topTrailingRadius: cornerRadius,
      style: .circular
    )
    .fill(Color(white: 0.12))
  }
}

struct UnreadCountBadge: View {
  let count: Int
  let size: CGFloat
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
    // Monospaced digits keep same-length counts at one width, so a count
    // change never resizes the badge.
    .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
  }

  var body: some View {
    Text("\(count)")
      .font(badgeFont)
      .contentTransition(.numericText())
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
      .background(CornerBadgeSlab(size: size, cornerRadius: cornerRadius))
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
  let cornerRadius: CGFloat

  #if os(tvOS)
    static let defaultSize: CGFloat = 24
  #else
    static let defaultSize: CGFloat = 12
  #endif

  @State private var measuredHeight: CGFloat = 0

  init(size: CGFloat = defaultSize, cornerRadius: CGFloat = 8) {
    self.size = size
    self.cornerRadius = cornerRadius
  }

  private var badgeFont: Font {
    .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
  }

  var body: some View {
    // The glyph has no line box of its own; a hidden digit in the count
    // badge's font supplies the identical height and width.
    Text(verbatim: "0")
      .font(badgeFont)
      .opacity(0)
      .accessibilityHidden(true)
      .overlay {
        Image(systemName: "checkmark")
          .font(.system(size: size * 0.85, weight: .bold))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, size * 0.6)
      .padding(.vertical, size * 0.35)
      .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
        measuredHeight = height
      }
      .frame(minWidth: measuredHeight)
      .background(CornerBadgeSlab(size: size, cornerRadius: cornerRadius))
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
