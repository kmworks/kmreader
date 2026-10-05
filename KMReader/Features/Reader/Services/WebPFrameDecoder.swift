import CoreGraphics
import Foundation
import libwebp

nonisolated final class WebPFrameDecoder: AnimatedFrameDecoder {
  let timeline: AnimatedImageTimeline

  private let mappedPointer: UnsafeMutableRawPointer
  private let mappedSize: Int
  private let animDecoder: OpaquePointer
  private let canvasWidth: Int
  private let canvasHeight: Int
  private let maxPixelSize: Int?

  init?(fileURL: URL, maxPixelSize: Int?) {
    // WebPAnimDecoder keeps reading from this pointer for its whole lifetime;
    // mmap keeps the compressed bytes file-backed so the kernel pages them in
    // on demand instead of the whole file sitting in memory.
    let fd = open(fileURL.path, O_RDONLY)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var fileStatus = stat()
    guard fstat(fd, &fileStatus) == 0, fileStatus.st_size > 0 else { return nil }
    mappedSize = Int(fileStatus.st_size)
    guard
      let pointer = mmap(nil, mappedSize, PROT_READ, MAP_PRIVATE, fd, 0),
      pointer != MAP_FAILED
    else { return nil }
    mappedPointer = pointer

    var webpData = WebPData(
      bytes: UnsafePointer(mappedPointer.assumingMemoryBound(to: UInt8.self)),
      size: mappedSize
    )

    var options = WebPAnimDecoderOptions()
    WebPAnimDecoderOptionsInit(&options)
    options.color_mode = MODE_rgbA
    options.use_threads = 1

    guard let animDecoder = WebPAnimDecoderNew(&webpData, &options) else {
      munmap(mappedPointer, mappedSize)
      return nil
    }
    self.animDecoder = animDecoder

    var info = WebPAnimInfo()
    WebPAnimDecoderGetInfo(animDecoder, &info)
    canvasWidth = Int(info.canvas_width)
    canvasHeight = Int(info.canvas_height)
    let frameCount = Int(info.frame_count)
    guard frameCount > 0, canvasWidth > 0, canvasHeight > 0 else {
      WebPAnimDecoderDelete(animDecoder)
      munmap(mappedPointer, mappedSize)
      return nil
    }
    self.maxPixelSize = maxPixelSize

    // Frame durations and loop count come from the demuxer, which reads the
    // container metadata without decoding pixels.
    guard let demux = WebPDemux(&webpData) else {
      WebPAnimDecoderDelete(animDecoder)
      munmap(mappedPointer, mappedSize)
      return nil
    }
    var startTimes: [Double] = []
    startTimes.reserveCapacity(frameCount)
    var elapsed: Double = 0
    var iterator = WebPIterator()
    for frameNumber in 1...frameCount {
      startTimes.append(elapsed)
      if WebPDemuxGetFrame(demux, Int32(frameNumber), &iterator) != 0 {
        elapsed += Double(iterator.duration) / 1000
        WebPDemuxReleaseIterator(&iterator)
      }
    }
    let loopCount = Int(WebPDemuxGetI(demux, WEBP_FF_LOOP_COUNT))
    WebPDemuxDelete(demux)

    timeline = AnimatedImageTimeline(
      frameStartTimes: startTimes,
      loopDuration: elapsed,
      loopCount: loopCount
    )
  }

  deinit {
    WebPAnimDecoderDelete(animDecoder)
    munmap(mappedPointer, mappedSize)
  }

  func decodeNextFrame() -> CGImage? {
    if WebPAnimDecoderHasMoreFrames(animDecoder) == 0 {
      WebPAnimDecoderReset(animDecoder)
    }
    var buffer: UnsafeMutablePointer<UInt8>?
    var timestamp: Int32 = 0
    guard WebPAnimDecoderGetNext(animDecoder, &buffer, &timestamp) != 0, let buffer else { return nil }
    return renderFrame(buffer)
  }

  private func renderFrame(_ buffer: UnsafeMutablePointer<UInt8>) -> CGImage? {
    let scale: CGFloat
    if let maxPixelSize, maxPixelSize > 0 {
      scale = min(
        CGFloat(maxPixelSize) / CGFloat(max(canvasWidth, canvasHeight)),
        1
      )
    } else {
      scale = 1
    }
    let targetWidth = max(1, Int((CGFloat(canvasWidth) * scale).rounded()))
    let targetHeight = max(1, Int((CGFloat(canvasHeight) * scale).rounded()))

    // The decoder-owned buffer is reused by the next WebPAnimDecoderGetNext
    // call, so pixels are drawn into our own context right away.
    guard
      let provider = CGDataProvider(
        dataInfo: nil,
        data: buffer,
        size: canvasWidth * canvasHeight * 4,
        releaseData: { _, _, _ in }
      ),
      let frame = CGImage(
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: canvasWidth * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      ),
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(frame, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage()
  }
}
