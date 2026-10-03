import CoreGraphics

nonisolated struct TranslatedBubble: Sendable {
  /// Bubble interior bounding box, pixel coordinates, top-left origin.
  let regionRect: CGRect
  /// Page-sized mask, white marks the bubble interior.
  let maskImage: CGImage
  let backgroundColor: CGColor
  let sourceText: String
  let translatedText: String
}
