//
// ShimmerModifier.swift
//
//

import SwiftUI

/// Animated highlight band sweeping across a placeholder surface. Driven by
/// the shared `ShimmerClock`; Reduce Motion falls back to the static
/// placeholder.
struct ShimmerModifier: ViewModifier {
  let cornerRadius: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content
        .overlay { ShimmerSweep(cornerRadius: cornerRadius) }
        .onAppear { ShimmerClock.shared.retain() }
        .onDisappear { ShimmerClock.shared.release() }
    }
  }
}

private struct ShimmerSweep: View {
  let cornerRadius: CGFloat

  /// Band travels the view width plus its own width, so it is fully
  /// off-screen at both phase ends and the repeatForever wrap is invisible.
  var body: some View {
    GeometryReader { proxy in
      let band = min(250, proxy.size.height)
      LinearGradient(
        colors: [highlight.opacity(0), highlight, highlight.opacity(0)],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(width: band)
      .offset(x: -band + ShimmerClock.shared.phase * (proxy.size.width + band))
      // GeometryReader centers children; the offset math anchors at leading.
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    .allowsHitTesting(false)
  }

  /// System background at low alpha reads as a light sweep over the gray
  /// placeholder in both light and dark mode.
  private var highlight: Color {
    PlatformHelper.systemBackgroundColor.opacity(0.4)
  }
}

extension View {
  func shimmer(cornerRadius: CGFloat) -> some View {
    modifier(ShimmerModifier(cornerRadius: cornerRadius))
  }
}
