//
// HorizontalCardPalette.swift
//
//

import SwiftUI

/// Text colors for horizontal cards, derived from the cover tint: on the tint
/// all text is white at graded opacities so it stays readable (Apple Books
/// style); on the fallback card background the adaptive colors apply.
struct HorizontalCardPalette {
  let isTinted: Bool

  var titleColor: Color { isTinted ? .white : .primary }
  var seriesColor: Color { isTinted ? .white.opacity(0.85) : .primary }
  var metaColor: Color { isTinted ? .white.opacity(0.7) : .secondary }
}
