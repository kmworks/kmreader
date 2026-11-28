//
// EpubReaderControlGlyph.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Corner-button glyph backed by hidden copies of every corner glyph so all
  /// buttons share identical intrinsic width and height, producing identical
  /// glass circle diameters regardless of glyph shape.
  ///
  /// Calibrated to Apple Books: ~45.7pt circles (~11.3% of screen width),
  /// ~17–20pt light icons, and ~14pt inner padding at `.controlSize(.regular)`.
  struct EpubReaderControlGlyph: View {
    static let defaultFont: Font = .title2.weight(.light)
    static let defaultPadding: CGFloat = 3

    let systemName: String
    let font: Font

    init(systemName: String, font: Font = Self.defaultFont) {
      self.systemName = systemName
      self.font = font
    }

    var body: some View {
      ZStack {
        Image(systemName: AppIcon.close).hidden()
        Image(systemName: AppIcon.bookmark).hidden()
        Image(systemName: AppIcon.returnToPrevious).hidden()
        Image(systemName: systemName)
      }
      .font(font)
      .padding(Self.defaultPadding)
    }
  }
#endif
