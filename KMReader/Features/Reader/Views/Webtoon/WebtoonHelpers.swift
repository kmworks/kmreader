//
// WebtoonHelpers.swift
//
//

import CoreGraphics
import Foundation
import ImageIO

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@MainActor
func scheduleOnMain(after delay: TimeInterval, action: @escaping () -> Void) {
  Task { @MainActor in
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    action()
  }
}

struct InitialScrollRetrier {
  typealias DelayScheduler = @MainActor (TimeInterval, @escaping () -> Void) -> Void

  private(set) var attempts: Int = 0
  let maxRetries: Int

  mutating func reset() {
    attempts = 0
  }

  @MainActor
  mutating func schedule(
    after delay: TimeInterval,
    using scheduler: DelayScheduler,
    action: @escaping () -> Void
  ) {
    guard attempts < maxRetries else { return }
    attempts += 1
    scheduler(delay, action)
  }
}

struct WebtoonPageHeightCache {
  var heights: [ReaderPageID: CGFloat] = [:]
  var lastPageWidth: CGFloat = 0

  mutating func reset() {
    heights.removeAll()
  }

  mutating func retainHeights(for pageIDs: Set<ReaderPageID>) {
    heights = heights.filter { pageIDs.contains($0.key) }
  }

  mutating func rescaleIfNeeded(newWidth: CGFloat) {
    if lastPageWidth > 0, abs(lastPageWidth - newWidth) > 0.1 {
      let scaleFactor = newWidth / lastPageWidth
      if scaleFactor.isFinite && scaleFactor > 0 {
        for (index, height) in heights {
          heights[index] = height * scaleFactor
        }
      }
    }
    lastPageWidth = newWidth
  }

  func hasHeight(for pageID: ReaderPageID) -> Bool {
    heights[pageID] != nil
  }

  mutating func height(
    for pageID: ReaderPageID,
    page: BookPage,
    pageWidth: CGFloat
  ) -> CGFloat {
    guard pageWidth > 0 else { return 0 }
    if let cached = heights[pageID] {
      return cached
    }
    if let width = page.width, let height = page.height, width > 0 {
      let ratio = CGFloat(height) / CGFloat(width)
      if ratio.isFinite && ratio > 0 {
        let targetHeight = pageWidth * ratio
        heights[pageID] = targetHeight
        return targetHeight
      }
    }
    return max(pageWidth, 1)
  }

  mutating func updateHeight(
    for pageID: ReaderPageID,
    pixelSize: CGSize,
    pageWidth: CGFloat
  ) -> Bool {
    guard let targetHeight = webtoonMeasuredHeight(pixelSize: pixelSize, pageWidth: pageWidth) else {
      return false
    }

    if let cachedHeight = heights[pageID], abs(cachedHeight - targetHeight) < 0.5 {
      return false
    }

    heights[pageID] = targetHeight
    return true
  }
}

func webtoonMeasuredHeight(pixelSize: CGSize, pageWidth: CGFloat) -> CGFloat? {
  guard pageWidth > 0, pixelSize.width > 0, pixelSize.height > 0 else { return nil }
  let ratio = pixelSize.height / pixelSize.width
  guard ratio.isFinite, ratio > 0 else { return nil }
  let targetHeight = pageWidth * ratio
  guard targetHeight.isFinite, targetHeight > 0 else { return nil }
  return targetHeight
}

func webtoonProbePixelSize(at fileURL: URL) -> CGSize? {
  let options = [kCGImageSourceShouldCache: false] as CFDictionary
  guard
    let source = CGImageSourceCreateWithURL(fileURL as CFURL, options),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
    let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
    pixelWidth > 0,
    pixelHeight > 0
  else {
    return nil
  }

  // Layout must match the displayed bitmap: EXIF 5–8 swap the axes.
  let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
  if (5...8).contains(orientation) {
    return CGSize(width: pixelHeight, height: pixelWidth)
  }
  return CGSize(width: pixelWidth, height: pixelHeight)
}

func webtoonPixelSize(from image: PlatformImage) -> CGSize? {
  #if os(iOS) || os(tvOS)
    if let cgImage = image.cgImage {
      // cgImage dims are raw; the ±90° orientations swap the display axes.
      if [.left, .right, .leftMirrored, .rightMirrored].contains(image.imageOrientation) {
        return CGSize(width: cgImage.height, height: cgImage.width)
      }
      return CGSize(width: cgImage.width, height: cgImage.height)
    }
    if let ciImage = image.ciImage {
      let extent = ciImage.extent.integral
      if extent.width > 0, extent.height > 0 {
        return CGSize(width: extent.width, height: extent.height)
      }
    }
    let size = image.size
    let scale = image.scale
    guard size.width > 0, size.height > 0, scale > 0 else { return nil }
    return CGSize(width: size.width * scale, height: size.height * scale)
  #elseif os(macOS)
    for representation in image.representations where representation.pixelsWide > 0 && representation.pixelsHigh > 0 {
      return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }

    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    return size
  #endif
}
