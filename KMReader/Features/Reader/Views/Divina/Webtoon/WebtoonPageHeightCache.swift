import CoreGraphics

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
