//
// PanelPageRaster.swift
//
// Downsampled background mask of a page, consumed by the reading-order gutter probe
// (see PanelGutterProbe). A cell is background when its 3x3 neighborhood range is low — no ink,
// stroke, or texture — regardless of level, so white paper, solid-black gutters, and flat
// fills all qualify while line art, text, screentone, and speed-lines do not. Built once
// per page off the main actor and shared by every probe on that page.
//

import CoreGraphics
import Foundation

nonisolated struct PanelPageRaster: Sendable {
  /// Working resolution (long side). High enough that a thin drawn gutter stays several
  /// cells wide after the 3x3 range test eats one cell from each border.
  static let longSide = 1536
  /// 3x3 neighborhood range above this marks a cell as ink/texture rather than background.
  static let textureRange = 70

  /// Row-major background flags, `width * height`.
  let background: [Bool]
  let width: Int
  let height: Int

  /// Build the mask from the page image, off the main actor.
  static func make(from image: CGImage) async -> PanelPageRaster? {
    await Task.detached(priority: Task.currentPriority) { build(from: image) }.value
  }

  private static func build(from image: CGImage) -> PanelPageRaster? {
    let w0 = image.width
    let h0 = image.height
    guard w0 > 0, h0 > 0 else { return nil }
    let scale = Double(longSide) / Double(max(w0, h0))
    let w = max(1, Int((Double(w0) * scale).rounded()))
    let h = max(1, Int((Double(h0) * scale).rounded()))

    var pixels = [UInt8](repeating: 0, count: w * h)
    let space = CGColorSpaceCreateDeviceGray()
    let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let base = raw.baseAddress,
        let ctx = CGContext(
          data: base, width: w, height: h, bitsPerComponent: 8,
          bytesPerRow: w, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else { return false }
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard ok else { return nil }

    // Separable sliding 3x3 min/max: rows first, then columns.
    var rowMin = [UInt8](repeating: 0, count: w * h)
    var rowMax = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h {
      let row = y * w
      for x in 0..<w {
        var lo = pixels[row + x]
        var hi = lo
        if x > 0 {
          lo = min(lo, pixels[row + x - 1])
          hi = max(hi, pixels[row + x - 1])
        }
        if x + 1 < w {
          lo = min(lo, pixels[row + x + 1])
          hi = max(hi, pixels[row + x + 1])
        }
        rowMin[row + x] = lo
        rowMax[row + x] = hi
      }
    }
    var background = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
      let row = y * w
      for x in 0..<w {
        var lo = rowMin[row + x]
        var hi = rowMax[row + x]
        if y > 0 {
          lo = min(lo, rowMin[row - w + x])
          hi = max(hi, rowMax[row - w + x])
        }
        if y + 1 < h {
          lo = min(lo, rowMin[row + w + x])
          hi = max(hi, rowMax[row + w + x])
        }
        background[row + x] = Int(hi) - Int(lo) <= textureRange
      }
    }
    return PanelPageRaster(background: background, width: w, height: h)
  }
}
