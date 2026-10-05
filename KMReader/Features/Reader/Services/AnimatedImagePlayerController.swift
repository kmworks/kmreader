import Foundation
import QuartzCore

#if os(macOS)
  import AppKit
#endif

/// Plays an animated image (WebP via libwebp, GIF via ImageIO) into a CALayer.
/// A display link computes the frame that should be visible right now from the
/// elapsed time (time-driven, so slow decoders drop frames instead of slowing
/// the animation), while a single background task decodes sequentially ahead of
/// it and hands frames back to the layer.
@MainActor
final class AnimatedImagePlayerController: NSObject {
  private weak var targetLayer: CALayer?
  #if os(macOS)
    private weak var targetView: NSView?
  #endif
  private var currentSourceFileURL: URL?
  private var targetMaxPixelSize: Int?
  private var timeline: AnimatedImageTimeline?
  private var playbackTask: Task<Void, Never>?
  private var targetContinuation: AsyncStream<UInt64>.Continuation?
  private var displayLink: CADisplayLink?
  private var startTimestamp: CFTimeInterval = 0
  private var currentTargetTick: UInt64 = 0
  private var playbackGeneration: UInt64 = 0

  #if os(macOS)
    // CADisplayLink on macOS can only be created from a view.
    func start(sourceFileURL: URL, targetView: NSView) {
      guard let targetLayer = targetView.layer else { return }
      self.targetView = targetView
      startPlayback(sourceFileURL: sourceFileURL, targetLayer: targetLayer)
    }
  #else
    func start(sourceFileURL: URL, targetLayer: CALayer) {
      startPlayback(sourceFileURL: sourceFileURL, targetLayer: targetLayer)
    }
  #endif

  private func startPlayback(sourceFileURL: URL, targetLayer: CALayer) {
    let targetMaxPixelSize = resolvedMaxPixelSize(for: targetLayer)
    if self.targetLayer === targetLayer,
      currentSourceFileURL == sourceFileURL,
      self.targetMaxPixelSize == targetMaxPixelSize,
      playbackTask != nil
    {
      return
    }

    stop()

    self.currentSourceFileURL = sourceFileURL
    self.targetLayer = targetLayer
    self.targetMaxPixelSize = targetMaxPixelSize
    let generation = nextPlaybackGeneration()

    let (targetStream, targetContinuation) = AsyncStream<UInt64>.makeStream()
    self.targetContinuation = targetContinuation

    playbackTask = Task.detached(priority: .userInitiated) { [weak self] in
      guard
        let decoder = AnimatedImageSupport.makeFrameDecoder(
          fileURL: sourceFileURL,
          maxPixelSize: targetMaxPixelSize
        ),
        decoder.timeline.frameCount > 1
      else {
        return
      }

      let timeline = decoder.timeline
      let ready = await MainActor.run { [weak self] () -> Bool in
        guard let self, self.playbackGeneration == generation else { return false }
        self.beginDisplay(timeline: timeline)
        return true
      }
      guard ready else { return }

      var cursor: UInt64 = 0
      var target: UInt64 = 0
      for await newTarget in targetStream {
        target = max(target, newTarget)
        while cursor <= target {
          if Task.isCancelled { return }
          guard let frame = decoder.decodeNextFrame() else { return }
          let tick = cursor
          cursor &+= 1
          // Only the newest frame reaches the layer; intermediate decodes exist
          // just to keep the sequential decoder in sync.
          if tick >= target {
            await MainActor.run { [weak self] in
              guard let self, self.playbackGeneration == generation else { return }
              self.targetLayer?.contents = frame
            }
          }
        }
      }
    }
  }

  func stop() {
    _ = nextPlaybackGeneration()
    displayLink?.invalidate()
    displayLink = nil
    targetContinuation?.finish()
    targetContinuation = nil
    playbackTask?.cancel()
    playbackTask = nil
    timeline = nil
    targetLayer?.contents = nil
    targetLayer = nil
    #if os(macOS)
      targetView = nil
    #endif
    currentSourceFileURL = nil
    targetMaxPixelSize = nil
  }

  private func beginDisplay(timeline: AnimatedImageTimeline) {
    self.timeline = timeline
    startTimestamp = CACurrentMediaTime()
    currentTargetTick = 0
    #if os(macOS)
      guard
        let displayLink = targetView?.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
      else { return }
    #else
      let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
    #endif
    displayLink.add(to: .main, forMode: .common)
    self.displayLink = displayLink
    targetContinuation?.yield(0)
  }

  @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
    guard let timeline else { return }
    guard let tick = timeline.targetTick(atElapsed: displayLink.timestamp - startTimestamp) else {
      // Finite loop count exhausted: freeze on the last frame.
      displayLink.invalidate()
      self.displayLink = nil
      targetContinuation?.finish()
      targetContinuation = nil
      return
    }
    if tick != currentTargetTick {
      currentTargetTick = tick
      targetContinuation?.yield(tick)
    }
  }

  private func resolvedMaxPixelSize(for targetLayer: CALayer) -> Int? {
    let bounds = targetLayer.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let scale = targetLayer.contentsScale > 0 ? targetLayer.contentsScale : 2
    let maxDimension = max(bounds.width, bounds.height) * scale
    guard maxDimension.isFinite, maxDimension > 0 else { return nil }
    return Int(ceil(maxDimension))
  }

  private func nextPlaybackGeneration() -> UInt64 {
    playbackGeneration &+= 1
    return playbackGeneration
  }
}
