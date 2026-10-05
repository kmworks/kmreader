import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

enum AnimatedImageSupport {
  nonisolated static func isAnimatedImageFile(at fileURL: URL) -> Bool {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options) else {
      return false
    }
    return CGImageSourceGetCount(source) > 1
  }

  nonisolated static func posterImage(from fileURL: URL) -> PlatformImage? {
    guard
      let decoder = makeFrameDecoder(fileURL: fileURL, maxPixelSize: nil),
      let cgImage = decoder.decodeNextFrame()
    else {
      return nil
    }
    #if os(macOS)
      return NSImage(
        cgImage: cgImage,
        size: NSSize(width: cgImage.width, height: cgImage.height)
      )
    #else
      return UIImage(cgImage: cgImage)
    #endif
  }

  nonisolated static func makeFrameDecoder(fileURL: URL, maxPixelSize: Int?) -> (any AnimatedFrameDecoder)? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard
      let source = CGImageSourceCreateWithURL(fileURL as CFURL, options),
      let type = CGImageSourceGetType(source)
    else {
      return nil
    }
    if type == UTType.webP.identifier as CFString {
      return WebPFrameDecoder(fileURL: fileURL, maxPixelSize: maxPixelSize)
    }
    if type == UTType.gif.identifier as CFString {
      return GIFFrameDecoder(fileURL: fileURL, maxPixelSize: maxPixelSize)
    }
    return nil
  }
}
