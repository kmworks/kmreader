import CoreGraphics
import Foundation
import ImageIO

nonisolated final class GIFFrameDecoder: AnimatedFrameDecoder {
  let timeline: AnimatedImageTimeline

  private let source: CGImageSource
  private let frameCount: Int
  private let maxPixelSize: Int?
  private var nextFrameIndex = 0

  init?(fileURL: URL, maxPixelSize: Int?) {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0 else { return nil }
    self.source = source
    self.frameCount = frameCount
    self.maxPixelSize = maxPixelSize

    var startTimes: [Double] = []
    startTimes.reserveCapacity(frameCount)
    var elapsed: Double = 0
    for index in 0..<frameCount {
      startTimes.append(elapsed)
      elapsed += Self.frameDuration(source: source, index: index)
    }
    // Without a NETSCAPE looping extension a GIF plays once.
    var loopCount = 1
    if let properties = CGImageSourceCopyProperties(source, nil) as? [String: Any],
      let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
      let count = gif[kCGImagePropertyGIFLoopCount as String] as? Int
    {
      loopCount = count
    }
    timeline = AnimatedImageTimeline(
      frameStartTimes: startTimes,
      loopDuration: elapsed,
      loopCount: loopCount
    )
  }

  func decodeNextFrame() -> CGImage? {
    if nextFrameIndex >= frameCount {
      nextFrameIndex = 0
    }
    let index = nextFrameIndex
    nextFrameIndex += 1

    guard let maxPixelSize, maxPixelSize > 0 else {
      return CGImageSourceCreateImageAtIndex(source, index, nil)
    }
    let options =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, index, options)
  }

  private static func frameDuration(source: CGImageSource, index: Int) -> Double {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
      let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
    else {
      return 0.1
    }
    let delay =
      (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
      ?? (gif[kCGImagePropertyGIFDelayTime as String] as? Double)
      ?? 0.1
    // Browsers clamp near-zero GIF delays; unclamped 0 would spin the decoder.
    return max(delay, 0.02)
  }
}
