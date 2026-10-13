//
// ShimmerModifier.swift
//
//

import SwiftUI

/// Sweeps an animated highlight band across a placeholder surface; Reduce
/// Motion falls back to the static placeholder.
struct ShimmerModifier: ViewModifier {
  let cornerRadius: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content
        .overlay { ShimmerSweepRepresentable(cornerRadius: cornerRadius) }
    }
  }
}

extension View {
  func shimmer(cornerRadius: CGFloat) -> some View {
    modifier(ShimmerModifier(cornerRadius: cornerRadius))
  }
}

#if os(iOS) || os(tvOS)
  private struct ShimmerSweepRepresentable: UIViewRepresentable {
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> ShimmerSweepView {
      let view = ShimmerSweepView()
      view.cornerRadius = cornerRadius
      return view
    }

    func updateUIView(_ uiView: ShimmerSweepView, context: Context) {
      guard uiView.cornerRadius != cornerRadius else { return }
      uiView.cornerRadius = cornerRadius
    }
  }
#else
  private struct ShimmerSweepRepresentable: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> ShimmerSweepView {
      let view = ShimmerSweepView()
      view.cornerRadius = cornerRadius
      return view
    }

    func updateNSView(_ nsView: ShimmerSweepView, context: Context) {
      guard nsView.cornerRadius != cornerRadius else { return }
      nsView.cornerRadius = cornerRadius
    }
  }
#endif
