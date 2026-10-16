import CoreGraphics
import Foundation
import ImageIO

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

func webtoonMeasuredHeight(pixelSize: CGSize, pageWidth: CGFloat) -> CGFloat? {
  guard pageWidth > 0, pixelSize.width > 0, pixelSize.height > 0 else { return nil }
  let ratio = pixelSize.height / pixelSize.width
  guard ratio.isFinite, ratio > 0 else { return nil }
  let targetHeight = pageWidth * ratio
  guard targetHeight.isFinite, targetHeight > 0 else { return nil }
  return targetHeight
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
