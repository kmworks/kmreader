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

  /// Pixel width needed to render the largest fixed cover surface of each
  /// device class 1:1: the wide detail rail on iPad/macOS, the centered
  /// detail hero on iPhone. Smaller surfaces take residual GPU minification
  /// from the one shared decode. tvOS targets 2x residual on its grid
  /// cards, which also lands the large showcase card at ~1:1.
  @MainActor
  static var maxCoverWidthPixels: CGFloat {
    #if os(iOS)
      if PlatformHelper.isPad {
        return LayoutConfig.detailWideCoverWidth * 2
      }
      return LayoutConfig.detailHeroCoverWidth * 3
    #elseif os(macOS)
      return LayoutConfig.detailWideCoverWidth * 2
    #else
      return 2 * LayoutConfig.gridCardWidth * 2
    #endif
  }

  /// Decodes the image at `url`, downsampling via ImageIO when the source
  /// exceeds the display requirement (aspect preserved).
  /// The requirement compares the source aspect with the √2 cover frame and
  /// follows the display mode: center-crop fills the frame (a taller cover
  /// binds its width `widthPixels`, a squatter one its height
  /// `widthPixels`·√2); fit shows the whole cover inside the frame, swapping
  /// the binding axis. ImageIO only accepts a long-edge maximum, so the
  /// satisfying scale is applied to the long edge.
  /// - Returns: the downsampled image, or nil when the source is already
  ///   below the requirement (the caller should take the normal decode
  ///   path) or when the image can't be read.
  /// - Note: The dimension probe reads image headers only; no decode happens
  ///   unless downsampling is actually needed.
  nonisolated static func decodeDownsampledIfNeeded(
    at url: URL, widthPixels: CGFloat, centerCropped: Bool
  ) async
    -> PlatformImage?
  {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { return nil }

    // EXIF orientations 5–8 swap the axes; compare in display orientation.
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let swapsAxes = (5...8).contains(orientation)
    let displayWidth = swapsAxes ? height : width
    let displayHeight = swapsAxes ? width : height

    let frameAspect = Double(CoverAspectRatio.heightToWidth)
    let target = Double(widthPixels)
    // Fit keeps the whole cover inside the frame: a tall cover is capped by
    // the frame height, a squat one by the width. Center-crop fills the
    // frame instead, swapping the binding axis.
    let bindsHeight = (displayHeight / displayWidth >= frameAspect) != centerCropped
    let scale =
      bindsHeight
      ? target * frameAspect / displayHeight
      : target / displayWidth
    guard scale < 1 else { return nil }

    let maxPixelSize = scale * max(displayWidth, displayHeight)
    let options: CFDictionary =
      [
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
