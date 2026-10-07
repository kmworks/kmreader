//
// ImageDecodeHelper.swift
//
//

import CoreGraphics
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

struct ImageDecodeHelper {
  /// Decodes image for display asynchronously to avoid blocking the caller and priority inversion.
  /// - Note: This function should be called from a background context to avoid blocking the main thread,
  /// especially on macOS where it performs synchronous drawing.
  nonisolated static func decodeForDisplay(_ image: PlatformImage) async -> PlatformImage {
    #if os(iOS) || os(tvOS)
      // Use the modern asynchronous decoding API which handles QoS internally
      return await image.byPreparingForDisplay() ?? image
    #elseif os(macOS)
      // On macOS, we perform the decode by drawing into a new context.
      // We assume the caller is running in an async background context (e.g. Task.detached or TaskGroup).
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
      }
      let width = cgImage.width
      let height = cgImage.height
      guard width > 0, height > 0 else { return image }

      let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
      let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

      guard
        let context = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else {
        return image
      }

      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      guard let decoded = context.makeImage() else { return image }
      return NSImage(cgImage: decoded, size: image.size)
    #else
      return image
    #endif
  }

  /// Max pixel dimension (long edge) for decoded covers, per platform.
  /// Covers are decoded once and shared across display sizes, so the cap is
  /// derived from the grid — where moiré was observed — targeting k2 ≈ 2 for
  /// the GPU bilinear stage (at ≤2x minification every source texel is sampled
  /// at least once; beyond that texels get skipped and aliasing starts).
  /// Since k2 = cap / (pt × screen scale), the cap scales with pixel density:
  /// - tvOS: 2 × 190pt × 2x = 760 (the 365pt showcase needs 730px, so no upscale)
  /// - iOS: 2 × 108pt × 3x = 650 (iPhone grid lands right on the line)
  /// - macOS: 2 × 104pt × 2x = 450
  /// Detail/hero images upscale at most ~1.1x, which never moirés. Covers at or
  /// below the cap skip downsampling entirely via the header-only probe.
  nonisolated static var maxCoverPixelDimension: CGFloat {
    #if os(tvOS)
      return 760
    #elseif os(macOS)
      return 450
    #else
      return 650
    #endif
  }

  /// Decodes the image at `url`, downsampling to `maxPixelSize` (long edge,
  /// aspect preserved) via ImageIO when the source exceeds the cap.
  /// - Returns: the downsampled image, or nil when the source is already at or
  ///   below the cap (the caller should take the normal decode path) or when
  ///   the image can't be read.
  /// - Note: The dimension probe reads image headers only; no decode happens
  ///   unless downsampling is actually needed.
  nonisolated static func decodeDownsampledIfNeeded(at url: URL, maxPixelSize: CGFloat) async
    -> PlatformImage?
  {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { return nil }
    guard max(width, height) > Double(maxPixelSize) else { return nil }

    let options: CFDictionary = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCache: false,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

    #if os(iOS) || os(tvOS)
      let image = UIImage(cgImage: cgImage)
      return await image.byPreparingForDisplay() ?? image
    #elseif os(macOS)
      return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    #else
      return nil
    #endif
  }
}
