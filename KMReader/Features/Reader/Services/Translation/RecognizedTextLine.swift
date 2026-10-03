import CoreGraphics

nonisolated struct RecognizedTextLine: Sendable {
  /// Pixel coordinates, top-left origin.
  let rect: CGRect
  let text: String

  var isVertical: Bool {
    rect.height > rect.width * 1.5
  }
}
