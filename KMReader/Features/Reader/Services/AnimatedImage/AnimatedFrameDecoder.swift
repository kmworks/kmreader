import CoreGraphics

/// Sequential decoder for animated image frames. Implementations wrap
/// forward-only decode APIs (WebPAnimDecoder, CGImageSource), so frames must be
/// consumed in order; looping is handled internally. Not Sendable — create and
/// drive from a single background task.
nonisolated protocol AnimatedFrameDecoder: AnyObject {
  var timeline: AnimatedImageTimeline { get }
  func decodeNextFrame() -> CGImage?
}
