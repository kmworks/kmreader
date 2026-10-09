import CoreGraphics

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

nonisolated struct ReaderUpscaleDecision: Sendable {
  enum SkipReason: Sendable {
    case disabled
    case belowAutoTriggerScale
    case invalidSourceSize
  }

  let shouldUpscale: Bool
  let requiredScale: CGFloat
  let reason: SkipReason?

  static func evaluate(
    mode: ReaderImageUpscalingMode,
    sourcePixelSize: CGSize,
    screenPixelSize: CGSize,
    autoTriggerScale: CGFloat
  ) -> ReaderUpscaleDecision {
    guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
      return ReaderUpscaleDecision(
        shouldUpscale: false,
        requiredScale: 0,
        reason: .invalidSourceSize
      )
    }

    let requiredScale = min(
      screenPixelSize.width / sourcePixelSize.width,
      screenPixelSize.height / sourcePixelSize.height
    )

    guard mode != .disabled else {
      return ReaderUpscaleDecision(
        shouldUpscale: false,
        requiredScale: requiredScale,
        reason: .disabled
      )
    }

    let safeAutoTriggerScale = max(autoTriggerScale, 1.0)
    guard requiredScale > safeAutoTriggerScale else {
      return ReaderUpscaleDecision(
        shouldUpscale: false,
        requiredScale: requiredScale,
        reason: .belowAutoTriggerScale
      )
    }

    return ReaderUpscaleDecision(
      shouldUpscale: true,
      requiredScale: requiredScale,
      reason: nil
    )
  }

  #if os(iOS) || os(tvOS)
    @MainActor
    static func screenPixelSize(for screen: UIScreen) -> CGSize {
      let size = screen.bounds.size
      let scale = screen.scale
      return CGSize(
        width: max(size.width * scale, 1),
        height: max(size.height * scale, 1)
      )
    }
  #elseif os(macOS)
    @MainActor
    static func screenPixelSize(for screen: NSScreen) -> CGSize {
      let frame = screen.frame
      let scale = screen.backingScaleFactor
      return CGSize(
        width: max(frame.width * scale, 1),
        height: max(frame.height * scale, 1)
      )
    }
  #endif
}
