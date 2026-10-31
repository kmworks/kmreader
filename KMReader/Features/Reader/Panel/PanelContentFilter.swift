//
// PanelContentFilter.swift
//
// Detector-agnostic pruning of phantom panels, applied before reading order and framing. A page can
// yield a boxed region that holds no figure or text AND is visually blank: a solid black bar, or the
// empty binding seam of a two-page spread read as a skinny panel. Such a box is not a real panel, so
// it is dropped here using only the page pixels — an edge-density "is anything actually drawn here"
// test — so genuine scenery and establishing panels (which always carry drawn edges) are never
// removed. Sparsely drawn panels (a single small object or sound effect on empty ground) dilute
// their global edge density, so blankness additionally requires that no local window concentrates
// ink: a real sparse panel clusters its edges in one spot, a true blank has none anywhere. Text and
// body boxes are never filtered. The fractions are scale-invariant, so they apply directly to
// normalized [0,1] boxes.
//

import CoreGraphics
import Foundation

nonisolated enum PanelContentFilter {
  /// A panel covering less than this fraction of the page is small enough to be a phantom sliver;
  /// anything larger is kept regardless (a real establishing panel can be content-light).
  static let maxPhantomArea = 0.06
  /// Grayscale gradient density below this fraction means nothing is drawn (solid bar / blank
  /// seam). Real art measures well above it; a black bar ~0.02, a blank seam ~0.00.
  static let blankEdgeDensity = 0.05
  /// Window edge (buffer pixels) for the local-concentration test. A candidate is only blank when
  /// BOTH the global density AND the densest sliding window fall below `blankEdgeDensity` — the
  /// window rescues sparsely drawn panels whose ink clusters in one spot (measured: real sparse
  /// panels reach 0.06–0.36 in their best window, uniform bars and voids stay at noise level).
  static let blankTileEdge = 32
  static let blankTileStride = 16
  /// A text/body counts as inside a panel when at least this fraction of it overlaps the panel.
  static let containmentFraction = 0.5
  /// Per-pixel grayscale gradient magnitude (0...255) above which a pixel is counted as an edge.
  static let edgeThreshold = 20.0
  /// Safety clamp on the grayscale buffer's long side. Realistic pages render at native size (so
  /// the edge density is measured at native resolution); only absurdly large scans downsample.
  static let maxBufferEdge = 4096

  /// Drop phantom panels from a detection. The geometry pre-check (small + no content inside) is
  /// cheap and runs inline; the pixel scan only happens when a candidate exists, and then off the
  /// main actor. Returns the input unchanged when nothing qualifies.
  static func filtered(_ detection: PageDetection, pageImage: CGImage) async -> PageDetection {
    let hasCandidate = detection.panels.contains {
      isCandidate($0, texts: detection.texts, bodies: detection.bodies)
    }
    guard hasCandidate else { return detection }
    return await Task.detached(priority: .utility) {
      apply(detection, pageImage: pageImage)
    }.value
  }

  // MARK: - Private

  /// A panel small enough and holding no text/body — the only kind worth the pixel scan.
  private static func isCandidate(_ panel: PanelRect, texts: [PanelRect], bodies: [PanelRect]) -> Bool {
    guard area(panel) < maxPhantomArea else { return false }
    let hasContent =
      texts.contains { contained($0, in: panel) >= containmentFraction }
      || bodies.contains { contained($0, in: panel) >= containmentFraction }
    return !hasContent
  }

  private static func apply(_ detection: PageDetection, pageImage: CGImage) -> PageDetection {
    guard let gray = grayBuffer(pageImage, maxEdge: maxBufferEdge) else { return detection }
    let kept = detection.panels.filter { panel in
      guard isCandidate(panel, texts: detection.texts, bodies: detection.bodies) else { return true }
      return edgeDensity(of: panel, in: gray) >= blankEdgeDensity
        || tileMaxDensity(of: panel, in: gray) >= blankEdgeDensity
    }
    guard kept.count != detection.panels.count else { return detection }
    return PageDetection(panels: kept, texts: detection.texts, bodies: detection.bodies)
  }

  // MARK: - Pixels

  /// Render the page to an 8-bit grayscale buffer, downsampling only past `maxEdge` on the long
  /// side. Returns the packed `[UInt8]` plus its dimensions, or nil if the context fails.
  private static func grayBuffer(_ image: CGImage, maxEdge: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
    let w0 = image.width
    let h0 = image.height
    guard w0 > 0, h0 > 0 else { return nil }
    let scale = min(1.0, Double(maxEdge) / Double(max(w0, h0)))
    let w = max(1, Int(Double(w0) * scale))
    let h = max(1, Int(Double(h0) * scale))

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
    return ok ? (pixels, w, h) : nil
  }

  /// Fraction of edge pixels inside the panel's pixel rect: pooled horizontal and vertical
  /// neighbor gradients above `edgeThreshold`.
  private static func edgeDensity(of panel: PanelRect, in gray: (pixels: [UInt8], width: Int, height: Int)) -> Double {
    let (pixels, width, height) = gray
    let x0 = max(0, Int(panel.x * Double(width)))
    let y0 = max(0, Int(panel.y * Double(height)))
    let x1 = min(width, Int((panel.x + panel.width) * Double(width)))
    let y1 = min(height, Int((panel.y + panel.height) * Double(height)))
    guard x1 - x0 >= 2, y1 - y0 >= 2 else { return 0 }

    var edges = 0
    var total = 0
    for y in y0..<y1 {
      let row = y * width
      for x in x0..<x1 {
        let v = Double(pixels[row + x])
        if x + 1 < x1 {
          if abs(Double(pixels[row + x + 1]) - v) > edgeThreshold { edges += 1 }
          total += 1
        }
        if y + 1 < y1 {
          if abs(Double(pixels[(y + 1) * width + x]) - v) > edgeThreshold { edges += 1 }
          total += 1
        }
      }
    }
    return total > 0 ? Double(edges) / Double(total) : 0
  }

  /// Max edge density over sliding `blankTileEdge` windows inside the panel's pixel rect. Each
  /// crop pixel contributes its right and down neighbor gradients (within the crop), so a window's
  /// density is its gradient-hit mean over two contributions per pixel — the windowed counterpart
  /// of `edgeDensity`. Windows clip to the crop when it is smaller than a full tile.
  private static func tileMaxDensity(of panel: PanelRect, in gray: (pixels: [UInt8], width: Int, height: Int)) -> Double
  {
    let (pixels, width, height) = gray
    let x0 = max(0, Int(panel.x * Double(width)))
    let y0 = max(0, Int(panel.y * Double(height)))
    let x1 = min(width, Int((panel.x + panel.width) * Double(width)))
    let y1 = min(height, Int((panel.y + panel.height) * Double(height)))
    let cw = x1 - x0
    let ch = y1 - y0
    guard cw >= 2, ch >= 2 else { return 0 }

    // Per-pixel gradient-hit counts (0...2) over the crop.
    var counts = [UInt8](repeating: 0, count: cw * ch)
    for y in 0..<ch {
      let row = (y0 + y) * width + x0
      let out = y * cw
      for x in 0..<cw {
        let v = Double(pixels[row + x])
        var c: UInt8 = 0
        if x + 1 < cw, abs(Double(pixels[row + x + 1]) - v) > edgeThreshold { c += 1 }
        if y + 1 < ch, abs(Double(pixels[row + width + x]) - v) > edgeThreshold { c += 1 }
        counts[out + x] = c
      }
    }

    var best = 0.0
    var wy = 0
    while wy == 0 || wy + blankTileEdge <= ch {
      let yEnd = min(ch, wy + blankTileEdge)
      var wx = 0
      while wx == 0 || wx + blankTileEdge <= cw {
        let xEnd = min(cw, wx + blankTileEdge)
        var sum = 0
        for y in wy..<yEnd {
          let row = y * cw
          for x in wx..<xEnd { sum += Int(counts[row + x]) }
        }
        let density = Double(sum) / Double((yEnd - wy) * (xEnd - wx)) / 2.0
        best = max(best, density)
        if wx + blankTileEdge >= cw { break }
        wx += blankTileStride
      }
      if wy + blankTileEdge >= ch { break }
      wy += blankTileStride
    }
    return best
  }

  // MARK: - Full-bleed art (splash → whole page)

  /// A splash zoom "closes in for no benefit" when the art bleeds to the page edges — cropping then
  /// loses the composition. Full-bleed art runs drawn detail into the outer frame ring; a croppable
  /// subject sits in whitespace margins. Detected as the edge density of the outer ring.
  static let fullBleedRingFraction = 0.12
  /// Gradient magnitude (0...255) above which a ring pixel is drawn detail (~0.12 of full scale).
  static let fullBleedEdgeThreshold = 0.12 * 255.0
  /// Downscale long side for the ring scan: small enough to smooth halftone / screentone (which
  /// otherwise reads as edges everywhere and washes out the signal), large enough to keep real edges.
  /// The density threshold below is calibrated to this size.
  static let fullBleedBufferEdge = 1024
  /// Ring edge density above this means the art bleeds to the edges: a splash beat drops to whole-page.
  static let fullBleedDensity = 0.30

  /// True when the page is full-bleed art, so a splash beat is dropped in favour of the whole page
  /// Runs the pixel scan off the main actor; only worth calling for splash-eligible pages.
  static func isFullBleed(_ image: CGImage) async -> Bool {
    await Task.detached(priority: .utility) {
      guard let gray = grayBuffer(image, maxEdge: fullBleedBufferEdge) else { return false }
      return ringEdgeDensity(gray) > fullBleedDensity
    }.value
  }

  /// Fraction of the outer-ring pixels whose 2px central-difference gradient magnitude exceeds
  /// `fullBleedEdgeThreshold`.
  private static func ringEdgeDensity(_ gray: (pixels: [UInt8], width: Int, height: Int)) -> Double {
    let (px, w, h) = gray
    guard w >= 3, h >= 3 else { return 0 }
    let rx = Int(Double(w) * fullBleedRingFraction)
    let ry = Int(Double(h) * fullBleedRingFraction)
    var edges = 0
    var total = 0
    for y in 0..<h {
      let inRingY = y < ry || y >= h - ry
      let row = y * w
      let rowUp = (y + 1) * w
      let rowDn = (y - 1) * w
      for x in 0..<w where inRingY || x < rx || x >= w - rx {
        let gx = (x > 0 && x < w - 1) ? Double(px[row + x + 1]) - Double(px[row + x - 1]) : 0
        let gy = (y > 0 && y < h - 1) ? Double(px[rowUp + x]) - Double(px[rowDn + x]) : 0
        if (gx * gx + gy * gy).squareRoot() > fullBleedEdgeThreshold { edges += 1 }
        total += 1
      }
    }
    return total > 0 ? Double(edges) / Double(total) : 0
  }

  // MARK: - Geometry (normalized boxes)

  private static func area(_ r: PanelRect) -> Double { max(0, r.width) * max(0, r.height) }

  /// Fraction of `inner`'s area that lies inside `outer`.
  private static func contained(_ inner: PanelRect, in outer: PanelRect) -> Double {
    let iw = max(0, min(inner.x + inner.width, outer.x + outer.width) - max(inner.x, outer.x))
    let ih = max(0, min(inner.y + inner.height, outer.y + outer.height) - max(inner.y, outer.y))
    let a = area(inner)
    return a > 0 ? (iw * ih) / a : 0
  }
}
