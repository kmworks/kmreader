import CoreGraphics
import CoreImage
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

enum MangaBubbleBackground {
  private static let ciContext = CIContext()

  static func feather(forBoxSize size: CGSize) -> CGFloat {
    min(14, max(6, min(size.width, size.height) * 0.12))
  }

  /// Text-tight boxes wrap the glyphs, so the ellipse must outgrow the box to
  /// still cover its corners (√2 to touch them); whole-bubble boxes already
  /// bound the bubble, so the ellipse stays inscribed.
  static func backgroundFrame(forBoxSize size: CGSize, boxKind: MangaTextBoxKind) -> CGRect {
    let coreScale: CGFloat = boxKind == .text ? 1.5 : 1
    let feather = feather(forBoxSize: size)
    let coreWidth = size.width * coreScale
    let coreHeight = size.height * coreScale
    return CGRect(
      x: (size.width - coreWidth) / 2 - feather,
      y: (size.height - coreHeight) / 2 - feather,
      width: coreWidth + feather * 2,
      height: coreHeight + feather * 2
    )
  }

  static func textFrame(forBoxSize size: CGSize, boxKind: MangaTextBoxKind) -> CGRect {
    switch boxKind {
    case .text:
      return CGRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(
        dx: min(5, max(2, size.width * 0.04)),
        dy: min(4, max(1, size.height * 0.03))
      )
    case .bubble:
      // the inscribed rect (1/√2) touches the ellipse rim; shrink further to
      // keep glyphs on the opaque core
      let scale: CGFloat = 0.6
      return CGRect(
        x: size.width * (1 - scale) / 2,
        y: size.height * (1 - scale) / 2,
        width: size.width * scale,
        height: size.height * scale
      )
    }
  }

  static func blobImage(size: CGSize, feather: CGFloat, color: CGColor) -> CGImage? {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0, feather * 2 < size.width, feather * 2 < size.height else { return nil }
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    let coreRect = CGRect(
      x: feather,
      y: feather,
      width: size.width - feather * 2,
      height: size.height - feather * 2
    )
    context.setFillColor(color)
    context.addPath(CGPath(ellipseIn: coreRect, transform: nil))
    context.fillPath()
    guard let solid = context.makeImage() else { return nil }
    // sigma ≈ feather/2.2 keeps the fade inside the feather band (α < 2% at the edge)
    let blurred = CIImage(cgImage: solid).applyingGaussianBlur(sigma: feather * 0.45)
    return ciContext.createCGImage(blurred, from: CGRect(x: 0, y: 0, width: size.width, height: size.height))
  }

  /// Estimates the bubble fill color behind a detected region. The dominant
  /// color of the band near the region's edges is the most robust guess: text
  /// and border strokes are the minority there, while the region center is
  /// covered by text.
  static func backgroundColor(in image: CGImage, normalizedBox box: CGRect) -> CGColor? {
    let pixelRect = CGRect(
      x: box.minX * CGFloat(image.width),
      y: box.minY * CGFloat(image.height),
      width: box.width * CGFloat(image.width),
      height: box.height * CGFloat(image.height)
    ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard pixelRect.width >= 8, pixelRect.height >= 8, let cropped = image.cropping(to: pixelRect)
    else { return nil }

    let scale = min(1, 64 / max(pixelRect.width, pixelRect.height))
    let sampleWidth = max(1, Int(pixelRect.width * scale))
    let sampleHeight = max(1, Int(pixelRect.height * scale))
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
    guard
      let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: sampleWidth * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .medium
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    let band = max(2, min(sampleWidth, sampleHeight) / 7)
    var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
    for y in 0..<sampleHeight {
      for x in 0..<sampleWidth {
        guard x < band || y < band || x >= sampleWidth - band || y >= sampleHeight - band else { continue }
        let offset = (y * sampleWidth + x) * 4
        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])
        let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
        var bucket = buckets[key] ?? (0, 0, 0, 0)
        bucket.count += 1
        bucket.r += r
        bucket.g += g
        bucket.b += b
        buckets[key] = bucket
      }
    }
    guard let winner = buckets.max(by: { $0.value.count < $1.value.count }), winner.value.count > 0
    else { return nil }
    return CGColor(
      srgbRed: CGFloat(winner.value.r) / CGFloat(winner.value.count) / 255,
      green: CGFloat(winner.value.g) / CGFloat(winner.value.count) / 255,
      blue: CGFloat(winner.value.b) / CGFloat(winner.value.count) / 255,
      alpha: 1
    )
  }

  // Sampled fills cluster near pure white/black, so a mid-gray luminance
  // threshold suffices to keep the text readable.
  static func textColor(on background: CGColor) -> CGColor {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let components = background.converted(to: space, intent: .defaultIntent, options: nil)?
        .components,
      components.count >= 3
    else { return CGColor(gray: 0, alpha: 1) }
    let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
    return luminance < 0.5 ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
  }

  static func multiply(_ color: CGColor, by tint: CGColor) -> CGColor {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let base = color.converted(to: space, intent: .defaultIntent, options: nil)?.components,
      let factors = tint.converted(to: space, intent: .defaultIntent, options: nil)?.components,
      base.count >= 3, factors.count >= 3
    else { return color }
    return CGColor(
      srgbRed: base[0] * factors[0],
      green: base[1] * factors[1],
      blue: base[2] * factors[2],
      alpha: 1
    )
  }

  /// Region boxes are normalized onto the image as displayed; rendering the
  /// image upright keeps sampled pixels in the same coordinate space even when
  /// the source bitmap carries a non-default orientation.
  static func normalizedCGImage(from image: PlatformImage) -> CGImage? {
    #if os(iOS) || os(tvOS)
      if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
        image.draw(at: .zero)
      }.cgImage
    #elseif os(macOS)
      return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    #endif
  }
}
