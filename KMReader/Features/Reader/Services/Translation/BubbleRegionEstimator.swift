import CoreGraphics
import Foundation

nonisolated enum BubbleRegionEstimator {
  struct BubbleDraft: Sendable {
    let lines: [RecognizedTextLine]
    let unionRect: CGRect
  }

  struct EstimatedBubble: Sendable {
    let regionRect: CGRect
    let maskImage: CGImage
    let backgroundColor: CGColor
  }

  enum EstimationResult: Sendable {
    case bubble(EstimatedBubble)
    case skipped(String)
  }

  private static let gridLongEdge: CGFloat = 768
  private static let colorDistanceThreshold: Double = 28
  private static let darkChannelFloor: Double = 128
  private static let minBackgroundCoverage: Double = 0.4
  private static let maxRegionPageFraction: Double = 0.35
  private static let maxRegionSeedAreaRatio: Double = 25

  static func groupIntoBubbles(_ lines: [RecognizedTextLine], pageSize: CGSize) -> [BubbleDraft] {
    let verticalLines = lines.filter(\.isVertical)
    let horizontalLines = lines.filter { !$0.isVertical }
    var groups = clusterVerticalLines(verticalLines) + clusterHorizontalLines(horizontalLines)

    // The single scans break a bubble's lines into separate drafts whenever other
    // bubbles interleave in the scan order; pull drafts back together when their
    // unions sit within a line-sized margin of each other.
    let mergeMargin = median(lines.map { min($0.rect.width, $0.rect.height) }) * 0.75
    var didMerge = true
    while didMerge {
      didMerge = false
      var merged: [BubbleDraft] = []
      var consumed = Set<Int>()
      for i in groups.indices where !consumed.contains(i) {
        var current = groups[i]
        let reach = current.unionRect.insetBy(dx: -mergeMargin, dy: -mergeMargin)
        for j in (i + 1)..<groups.count where !consumed.contains(j) {
          if reach.intersects(groups[j].unionRect) {
            current = BubbleDraft(
              lines: current.lines + groups[j].lines,
              unionRect: current.unionRect.union(groups[j].unionRect)
            )
            consumed.insert(j)
            didMerge = true
          }
        }
        merged.append(current)
      }
      groups = merged
    }
    return groups
  }

  struct PageGrid: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let blocked: [Bool]
    let scale: CGFloat
  }

  static func makePageGrid(for image: CGImage) -> PageGrid? {
    let pageWidth = image.width
    let pageHeight = image.height
    guard pageWidth > 0, pageHeight > 0 else { return nil }

    let scale = min(1, gridLongEdge / max(CGFloat(pageWidth), CGFloat(pageHeight)))
    let gridWidth = max(1, Int((CGFloat(pageWidth) * scale).rounded()))
    let gridHeight = max(1, Int((CGFloat(pageHeight) * scale).rounded()))

    guard let pixels = downscaledRGBAPixels(from: image, width: gridWidth, height: gridHeight),
      let blocked = darkChannelBlockedGrid(
        from: image,
        gridWidth: gridWidth,
        gridHeight: gridHeight
      )
    else { return nil }
    return PageGrid(width: gridWidth, height: gridHeight, pixels: pixels, blocked: blocked, scale: scale)
  }

  static func estimateRegion(for draft: BubbleDraft, in image: CGImage, grid: PageGrid) -> EstimationResult {
    let pageWidth = image.width
    let pageHeight = image.height
    guard pageWidth > 0, pageHeight > 0 else { return .skipped("invalid-page") }
    let pageSize = CGSize(width: pageWidth, height: pageHeight)

    let scale = grid.scale
    let gridWidth = grid.width
    let gridHeight = grid.height
    let pixels = grid.pixels

    let rawSeed = CGRect(
      x: draft.unionRect.origin.x * scale,
      y: draft.unionRect.origin.y * scale,
      width: draft.unionRect.width * scale,
      height: draft.unionRect.height * scale
    )
    let gridBounds = CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)
    let samplingRect =
      rawSeed
      .insetBy(dx: -rawSeed.width * 0.15, dy: -rawSeed.height * 0.15)
      .intersection(gridBounds)
      .integral
    let seed = rawSeed.intersection(gridBounds).integral
    guard seed.width >= 3, seed.height >= 3 else { return .skipped("seed-too-small") }

    guard let background = dominantLightColor(in: samplingRect, pixels: pixels, gridWidth: gridWidth) else {
      return .skipped("no-dominant-background")
    }

    let pixelCount = gridWidth * gridHeight
    var visited = [Bool](repeating: false, count: pixelCount)
    var queue = [Int]()
    queue.reserveCapacity(pixelCount / 4)

    let seedMinX = Int(seed.minX)
    let seedMaxX = Int(seed.maxX) - 1
    let seedMinY = Int(seed.minY)
    let seedMaxY = Int(seed.maxY) - 1
    for y in seedMinY...seedMaxY {
      for x in seedMinX...seedMaxX {
        let index = y * gridWidth + x
        if !grid.blocked[index],
          colorDistance(pixel: pixels, at: index, to: background) < colorDistanceThreshold
        {
          visited[index] = true
          queue.append(index)
        }
      }
    }
    guard !queue.isEmpty else { return .skipped("empty-flood") }

    var regionCount = 0
    var minX = gridWidth
    var maxX = 0
    var minY = gridHeight
    var maxY = 0
    var touchedEdges = 0
    var edgeFlags = (left: false, right: false, top: false, bottom: false)

    var head = 0
    while head < queue.count {
      let index = queue[head]
      head += 1
      regionCount += 1

      let x = index % gridWidth
      let y = index / gridWidth
      minX = min(minX, x)
      maxX = max(maxX, x)
      minY = min(minY, y)
      maxY = max(maxY, y)
      if x == 0 { edgeFlags.left = true }
      if x == gridWidth - 1 { edgeFlags.right = true }
      if y == 0 { edgeFlags.top = true }
      if y == gridHeight - 1 { edgeFlags.bottom = true }

      let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
      for (nx, ny) in neighbors where nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridHeight {
        let next = ny * gridWidth + nx
        guard !visited[next],
          !grid.blocked[next],
          colorDistance(pixel: pixels, at: next, to: background) < colorDistanceThreshold
        else { continue }
        visited[next] = true
        queue.append(next)
      }
    }

    for flag in [edgeFlags.left, edgeFlags.right, edgeFlags.top, edgeFlags.bottom] where flag {
      touchedEdges += 1
    }
    // Bail out conservatively: a region this large or this unconstrained is the
    // page background, not a bubble; painting over it would destroy the page.
    // The seed-area ratio catches floods that stay under the page fraction by
    // leaking only partway across the page.
    let regionArea = Double(maxX - minX + 1) * Double(maxY - minY + 1)
    let seedArea = Double(seed.width) * Double(seed.height)
    guard regionCount <= Int(Double(pixelCount) * maxRegionPageFraction) else {
      return .skipped("region-too-large")
    }
    guard touchedEdges < 3 else { return .skipped("region-leaks-to-edges") }
    guard seedArea > 0, regionArea <= seedArea * maxRegionSeedAreaRatio else {
      return .skipped("region-exceeds-seed-ratio")
    }

    // The interior flood only covers near-background pixels, leaving glyph-shaped
    // holes. Fill them by marking everything reachable from the page edges without
    // crossing the region; whatever is left unreachable is interior, glyphs included.
    var outside = [Bool](repeating: false, count: pixelCount)
    var outsideQueue = [Int]()
    outsideQueue.reserveCapacity(pixelCount / 4)
    for x in 0..<gridWidth {
      for y in [0, gridHeight - 1] {
        let index = y * gridWidth + x
        if !visited[index] && !outside[index] {
          outside[index] = true
          outsideQueue.append(index)
        }
      }
    }
    for y in 0..<gridHeight {
      for x in [0, gridWidth - 1] {
        let index = y * gridWidth + x
        if !visited[index] && !outside[index] {
          outside[index] = true
          outsideQueue.append(index)
        }
      }
    }
    var outsideHead = 0
    while outsideHead < outsideQueue.count {
      let index = outsideQueue[outsideHead]
      outsideHead += 1
      let x = index % gridWidth
      let y = index / gridWidth
      let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
      for (nx, ny) in neighbors where nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridHeight {
        let next = ny * gridWidth + nx
        if !visited[next] && !outside[next] {
          outside[next] = true
          outsideQueue.append(next)
        }
      }
    }

    var gridMask = [UInt8](repeating: 0, count: pixelCount)
    for index in 0..<pixelCount where !outside[index] {
      gridMask[index] = 255
    }
    guard
      let maskImage = pageSizedMask(
        from: gridMask,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        pageWidth: pageWidth,
        pageHeight: pageHeight
      )
    else { return .skipped("mask-failed") }

    let regionRect = CGRect(
      x: CGFloat(minX) / scale,
      y: CGFloat(minY) / scale,
      width: CGFloat(maxX - minX + 1) / scale,
      height: CGFloat(maxY - minY + 1) / scale
    ).intersection(CGRect(origin: .zero, size: pageSize))

    // The flood can leak past a weak border, inflating the region far beyond the
    // text; erasing there is harmless (near-background paint) but typesetting must
    // stay within sight of the original lines.
    let typesetRect = regionRect.intersection(
      draft.unionRect.insetBy(
        dx: -draft.unionRect.width * 0.25,
        dy: -draft.unionRect.height * 0.25
      )
    )

    let backgroundColor = CGColor(
      srgbRed: background.r / 255,
      green: background.g / 255,
      blue: background.b / 255,
      alpha: 1
    )
    return .bubble(
      EstimatedBubble(regionRect: typesetRect, maskImage: maskImage, backgroundColor: backgroundColor))
  }

  private static func clusterVerticalLines(_ lines: [RecognizedTextLine]) -> [BubbleDraft] {
    guard !lines.isEmpty else { return [] }
    // Vertical CJK columns read right-to-left, so chain columns in descending x.
    let sorted = lines.sorted { $0.rect.midX > $1.rect.midX }
    let medianWidth = median(sorted.map(\.rect.width))
    let gapThreshold = medianWidth * 1.2

    var drafts: [BubbleDraft] = []
    var currentLines = [sorted[0]]
    var unionRect = sorted[0].rect
    var previous = sorted[0]
    for line in sorted.dropFirst() {
      let gap = previous.rect.minX - line.rect.maxX
      let yOverlap = min(unionRect.maxY, line.rect.maxY) - max(unionRect.minY, line.rect.minY)
      if gap < gapThreshold && yOverlap > -medianWidth {
        currentLines.append(line)
        unionRect = unionRect.union(line.rect)
      } else {
        drafts.append(makeDraft(currentLines))
        currentLines = [line]
        unionRect = line.rect
      }
      previous = line
    }
    drafts.append(makeDraft(currentLines))
    return drafts
  }

  private static func clusterHorizontalLines(_ lines: [RecognizedTextLine]) -> [BubbleDraft] {
    guard !lines.isEmpty else { return [] }
    let sorted = lines.sorted { $0.rect.minY < $1.rect.minY }
    let medianHeight = median(sorted.map(\.rect.height))
    let gapThreshold = medianHeight * 1.2

    var drafts: [BubbleDraft] = []
    var currentLines = [sorted[0]]
    var unionRect = sorted[0].rect
    var previous = sorted[0]
    for line in sorted.dropFirst() {
      let gap = line.rect.minY - previous.rect.maxY
      // Bubbles sitting on the same horizontal band are separate unless their
      // x intervals actually meet; y proximity alone merges distinct bubbles.
      let xOverlap = min(unionRect.maxX, line.rect.maxX) - max(unionRect.minX, line.rect.minX)
      if gap < gapThreshold && xOverlap > -medianHeight {
        currentLines.append(line)
        unionRect = unionRect.union(line.rect)
      } else {
        drafts.append(makeDraft(currentLines))
        currentLines = [line]
        unionRect = line.rect
      }
      previous = line
    }
    drafts.append(makeDraft(currentLines))
    return drafts
  }

  private static func makeDraft(_ lines: [RecognizedTextLine]) -> BubbleDraft {
    let unionRect = lines.dropFirst().reduce(lines[0].rect) { $0.union($1.rect) }
    return BubbleDraft(lines: lines, unionRect: unionRect)
  }

  private static func median(_ values: [CGFloat]) -> CGFloat {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

  private static func downscaledRGBAPixels(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
    let bytesPerRow = width * 4
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    let buffer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    return Array(UnsafeBufferPointer(start: buffer, count: bytesPerRow * height))
  }

  /// Thin bubble outlines blur away under interpolated downscaling, so the flood's
  /// blocking map instead takes the minimum source-resolution luminance per grid
  /// cell (plus a one-pixel halo): the darkest stroke always survives.
  private static func darkChannelBlockedGrid(from image: CGImage, gridWidth: Int, gridHeight: Int) -> [Bool]? {
    let pageWidth = image.width
    let pageHeight = image.height
    guard let pixels = downscaledRGBAPixels(from: image, width: pageWidth, height: pageHeight) else {
      return nil
    }
    let scaleX = Double(pageWidth) / Double(gridWidth)
    let scaleY = Double(pageHeight) / Double(gridHeight)
    var grid = [Bool](repeating: false, count: gridWidth * gridHeight)
    for gy in 0..<gridHeight {
      let srcMinY = max(0, Int(Double(gy) * scaleY) - 1)
      let srcMaxY = min(pageHeight - 1, Int(Double(gy + 1) * scaleY) + 1)
      for gx in 0..<gridWidth {
        let srcMinX = max(0, Int(Double(gx) * scaleX) - 1)
        let srcMaxX = min(pageWidth - 1, Int(Double(gx + 1) * scaleX) + 1)
        var minLuminance = Double.greatestFiniteMagnitude
        for sy in srcMinY...srcMaxY {
          for sx in srcMinX...srcMaxX {
            let offset = (sy * pageWidth + sx) * 4
            let luminance =
              0.299 * Double(pixels[offset]) + 0.587 * Double(pixels[offset + 1])
              + 0.114 * Double(pixels[offset + 2])
            if luminance < minLuminance { minLuminance = luminance }
          }
        }
        grid[gy * gridWidth + gx] = minLuminance < darkChannelFloor
      }
    }
    return grid
  }

  /// Picks the dominant light color of the sampling rect as the bubble background.
  /// Glyphs are dark and barely vote; a real bubble interior is one flat light color
  /// covering most of the rect. Artwork either has no dominant light bin, or — when
  /// the artwork itself dominates — is caught by the region-size guard once the
  /// flood spills across the page.
  private static func dominantLightColor(
    in rect: CGRect,
    pixels: [UInt8],
    gridWidth: Int
  ) -> (r: Double, g: Double, b: Double)? {
    var bins: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
    var totalCount = 0
    let minX = Int(rect.minX)
    let maxX = Int(rect.maxX) - 1
    let minY = Int(rect.minY)
    let maxY = Int(rect.maxY) - 1
    for y in minY...maxY {
      for x in minX...maxX {
        totalCount += 1
        let offset = (y * gridWidth + x) * 4
        let r = Double(pixels[offset])
        let g = Double(pixels[offset + 1])
        let b = Double(pixels[offset + 2])
        guard 0.299 * r + 0.587 * g + 0.114 * b >= 128 else { continue }
        let key = ((Int(r) >> 4) << 8) | ((Int(g) >> 4) << 4) | (Int(b) >> 4)
        var bin = bins[key] ?? (count: 0, r: 0, g: 0, b: 0)
        bin.count += 1
        bin.r += r
        bin.g += g
        bin.b += b
        bins[key] = bin
      }
    }
    guard totalCount > 0,
      let dominant = bins.values.max(by: { $0.count < $1.count }),
      Double(dominant.count) / Double(totalCount) >= minBackgroundCoverage
    else { return nil }
    let count = Double(dominant.count)
    return (r: dominant.r / count, g: dominant.g / count, b: dominant.b / count)
  }

  private static func colorDistance(
    pixel pixels: [UInt8],
    at index: Int,
    to color: (r: Double, g: Double, b: Double)
  ) -> Double {
    let offset = index * 4
    let dr = Double(pixels[offset]) - color.r
    let dg = Double(pixels[offset + 1]) - color.g
    let db = Double(pixels[offset + 2]) - color.b
    return (dr * dr + dg * dg + db * db).squareRoot()
  }

  private static func pageSizedMask(
    from gridMask: [UInt8],
    gridWidth: Int,
    gridHeight: Int,
    pageWidth: Int,
    pageHeight: Int
  ) -> CGImage? {
    let graySpace = CGColorSpaceCreateDeviceGray()
    guard
      let gridContext = CGContext(
        data: nil,
        width: gridWidth,
        height: gridHeight,
        bitsPerComponent: 8,
        bytesPerRow: gridWidth,
        space: graySpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      ),
      let gridData = gridContext.data
    else { return nil }
    gridData.bindMemory(to: UInt8.self, capacity: gridMask.count).initialize(from: gridMask, count: gridMask.count)
    guard let gridImage = gridContext.makeImage() else { return nil }

    guard
      let pageContext = CGContext(
        data: nil,
        width: pageWidth,
        height: pageHeight,
        bitsPerComponent: 8,
        bytesPerRow: pageWidth,
        space: graySpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else { return nil }
    pageContext.interpolationQuality = .high
    pageContext.draw(gridImage, in: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
    return pageContext.makeImage()
  }
}
