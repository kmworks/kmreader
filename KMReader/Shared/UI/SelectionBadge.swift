//
// SelectionBadge.swift
//
//

import SwiftUI

/// Selection-mode checkbox: a gray outline circle that turns into a filled
/// accent checkmark when selected. `onCover` renders the badge legibly on top
/// of artwork (white on a dark scrim), like Photos.
struct SelectionBadge: View {
  let isSelected: Bool
  var onCover: Bool = false

  var body: some View {
    if onCover {
      ZStack {
        if !isSelected {
          Image(systemName: "circle.fill")
            .foregroundStyle(.black.opacity(0.35))
        }
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, Color.primary)
      }
      .font(.title3)
      .padding(8)
    } else {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.5))
    }
  }
}

extension View {
  /// Selection-mode emphasis: unselected items recede (shrink in place, gray
  /// out) so the picked ones stand out.
  func selectionDimmed(_ dimmed: Bool, scale: CGFloat) -> some View {
    self
      .scaleEffect(dimmed ? scale : 1)
      .opacity(dimmed ? 0.55 : 1)
      .saturation(dimmed ? 0.7 : 1)
  }
}
