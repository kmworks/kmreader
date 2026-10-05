import Foundation

/// Playback timeline of an animated image: cumulative frame start times within one
/// loop, the loop duration, and the loop count (0 = infinite). Positions are
/// expressed as absolute ticks (loopIndex * frameCount + frameIndex) so targets
/// increase monotonically across loop boundaries.
nonisolated struct AnimatedImageTimeline: Sendable {
  let frameStartTimes: [Double]
  let loopDuration: Double
  let loopCount: Int

  var frameCount: Int { frameStartTimes.count }

  /// Absolute tick to display at `elapsed` seconds after playback start, or nil
  /// once a finite loop count is exhausted (freeze on the last frame).
  func targetTick(atElapsed elapsed: Double) -> UInt64? {
    guard frameCount > 0, loopDuration > 0, elapsed >= 0 else { return 0 }
    let loopIndex = UInt64(elapsed / loopDuration)
    if loopCount > 0, loopIndex >= UInt64(loopCount) { return nil }
    let inLoop = elapsed - Double(loopIndex) * loopDuration
    var lo = 0
    var hi = frameCount - 1
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if frameStartTimes[mid] <= inLoop {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    return loopIndex &* UInt64(frameCount) &+ UInt64(lo)
  }
}
