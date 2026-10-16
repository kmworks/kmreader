//
// PlatformImage+ReaderRotation.swift
//

import CoreGraphics

#if os(iOS) || os(tvOS)
  import UIKit

  extension UIImage {
    func rotated(for rotation: ReaderRotation) -> UIImage {
      guard rotation != .none else { return self }

      let radians = CGFloat(rotation.degrees) * .pi / 180
      let rotatedSize = rotation.rotatedSize(size)

      let format = UIGraphicsImageRendererFormat()
      format.scale = scale
      let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
      return renderer.image { context in
        context.cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.cgContext.rotate(by: radians)
        draw(
          in: CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
          ))
      }
    }
  }
#elseif os(macOS)
  import AppKit

  extension NSImage {
    func rotated(for rotation: ReaderRotation) -> NSImage {
      guard rotation != .none else { return self }
      guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }

      let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
      let radians = CGFloat(rotation.degrees) * .pi / 180
      let rotatedSize = rotation.rotatedSize(sourceSize)

      let rotatedImage = NSImage(size: rotatedSize)
      rotatedImage.lockFocus()
      guard let context = NSGraphicsContext.current?.cgContext else {
        rotatedImage.unlockFocus()
        return self
      }
      context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
      context.rotate(by: radians)
      context.draw(
        cgImage,
        in: CGRect(
          x: -sourceSize.width / 2,
          y: -sourceSize.height / 2,
          width: sourceSize.width,
          height: sourceSize.height
        ))
      rotatedImage.unlockFocus()
      return rotatedImage
    }
  }
#endif
