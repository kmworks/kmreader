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
        // Fixed white/black palette: Color.primary would collide with the
        // white circle in dark mode and hide the checkmark.
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .black)
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
  /// Selection-mode emphasis: unselected items recede (shrink in place, veiled)
  /// so the picked ones stand out. A plain veil composites as one extra layer;
  /// opacity/saturation on the card would force an offscreen render pass of
  /// the whole subtree, which stalls scrolling in card grids.
  func selectionDimmed(_ dimmed: Bool, scale: CGFloat) -> some View {
    self
      .overlay {
        if dimmed {
          Color.selectionVeil
            .allowsHitTesting(false)
        }
      }
      .scaleEffect(dimmed ? scale : 1)
  }
}
