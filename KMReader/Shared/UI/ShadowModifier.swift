//
// ShadowModifier.swift
//
//

import SwiftUI

struct ShadowModifier: ViewModifier {
  let style: ShadowStyle
  let cornerRadius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    switch style {
    case .none:
      content
    case .basic, .platform:
      content
        .background(
          ShadowImageView(style: style, cornerRadius: cornerRadius)
        )
    }
  }
}

extension View {
  func shadowStyle(_ style: ShadowStyle, cornerRadius: CGFloat = 0) -> some View {
    modifier(ShadowModifier(style: style, cornerRadius: cornerRadius))
  }
}
