import SwiftUI

#if os(macOS)
  struct MouseHoverEffect: ViewModifier {
    @State private var isHovering = false

    var scale: CGFloat = 1.03

    func body(content: Content) -> some View {
      content
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .fill(.white)
            .opacity(isHovering ? 0.08 : 0)
            .allowsHitTesting(false)
        )
        .scaleEffect(isHovering ? scale : 1.0)
        .offset(y: isHovering ? -2 : 0)
        .animation(.appCurve(0.15), value: isHovering)
        .onHover { hovering in
          isHovering = hovering
        }
    }
  }
#endif

extension View {
  func macHoverEffect() -> some View {
    #if os(macOS)
      self.modifier(MouseHoverEffect())
    #else
      self
    #endif
  }

  /// Whole-card pointer hover for horizontal cards; inner buttons pass
  /// hoverEffect: false so the card lifts as one piece.
  @ViewBuilder
  func cardHoverEffect() -> some View {
    #if os(iOS)
      self.hoverEffect(.lift)
    #elseif os(macOS)
      self.modifier(MouseHoverEffect())
    #else
      self
    #endif
  }
}
