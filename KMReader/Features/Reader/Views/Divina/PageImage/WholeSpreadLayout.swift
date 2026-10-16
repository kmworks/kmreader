//
// WholeSpreadLayout.swift
//
//

import CoreGraphics

/// Sizes a whole spread in single-page presentation. Each half gets the scale a
/// single page gets in the same viewport, so the spread matches its neighbors'
/// size and pans when it is wider than the viewport.
enum WholeSpreadLayout {
  static func contentWidth(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
    guard imageSize.width > 0, imageSize.height > 0,
      viewportSize.width > 0, viewportSize.height > 0
    else {
      return viewportSize.width
    }

    let halfFitScale = min(
      viewportSize.width / (imageSize.width / 2),
      viewportSize.height / imageSize.height
    )
    let spreadWidth = imageSize.width * halfFitScale
    // Sub-point overflow would only add a pan the reader cannot see.
    return spreadWidth > viewportSize.width + 1 ? spreadWidth : viewportSize.width
  }
}
