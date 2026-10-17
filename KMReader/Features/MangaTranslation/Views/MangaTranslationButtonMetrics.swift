import CoreGraphics

/// Geometry of the per-page translate button, measured from the system Live
/// Text button: the circle diameter and its inset from the image's
/// bottom-right corner.
enum MangaTranslationButtonMetrics {
  static let size: CGFloat = 35
  static let cornerInset: CGFloat = 12

  /// The translate glyph is much wider than the phase icons, so it takes a
  /// smaller point size to keep every icon at roughly half the circle.
  static func glyphPointSize(for icon: String) -> CGFloat {
    icon == AppIcon.mangaTranslation ? 15 : 17
  }
}
