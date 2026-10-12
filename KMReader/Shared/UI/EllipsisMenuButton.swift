//
// EllipsisMenuButton.swift
//
//

import SwiftUI

struct EllipsisMenuButton<Content: View>: View {
  var color: Color = .secondary
  var hoverEffect: Bool = true
  @ViewBuilder let content: () -> Content

  var body: some View {
    // The hidden base keeps layout at glyph size; the overlay owns the 40x40 hit target.
    Image(systemName: AppIcon.more)
      .hidden()
      .overlay(
        Menu {
          content()
        } label: {
          Image(systemName: AppIcon.more)
            .foregroundColor(color)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .adaptiveButtonStyle(.plain, hoverEffect: hoverEffect)
      )
  }
}
