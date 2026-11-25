#if os(iOS)
  import Foundation

  /// Marks the short window after a touch that landed on a link in the page.
  ///
  /// WebKit activates in-chapter links itself, but the same touch also reaches
  /// the host's tap gesture, which otherwise runs a tap-zone action for a link
  /// tap and turns the page behind the footnote or cross-reference. The page JS
  /// reports the touch through `readerBridge` before the gesture resolves, and
  /// the host consumes the window instead of acting on the tap.
  @MainActor
  final class WebPubLinkTouchArm {
    /// Long enough to cover the gesture resolution, short enough that a stray
    /// message cannot swallow an unrelated later tap.
    private static let window: TimeInterval = 0.5

    private var armedUntil: TimeInterval = 0

    func arm() {
      armedUntil = Date().timeIntervalSinceReferenceDate + Self.window
    }

    /// Returns whether the pending tap belongs to a link, consuming the window.
    func consume() -> Bool {
      guard armedUntil > Date().timeIntervalSinceReferenceDate else { return false }
      armedUntil = 0
      return true
    }

    func reset() {
      armedUntil = 0
    }
  }
#endif
