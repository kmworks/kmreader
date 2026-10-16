//
// WebtoonScrollOffset.swift
//

import CoreGraphics

enum WebtoonScrollOffset {
  static func captureOffsetWithinPage(
    pageID: ReaderPageID,
    currentTopY: CGFloat,
    itemIndexForPage: (ReaderPageID) -> Int?,
    frameForItemIndex: (Int) -> CGRect?
  ) -> CGFloat? {
    guard let itemIndex = itemIndexForPage(pageID) else { return nil }
    guard let frame = frameForItemIndex(itemIndex) else { return nil }
    return offsetWithinItem(currentTopY: currentTopY, itemMinY: frame.minY)
  }

  static func targetTopYForPage(
    pageID: ReaderPageID,
    offsetWithinPage: CGFloat,
    itemIndexForPage: (ReaderPageID) -> Int?,
    frameForItemIndex: (Int) -> CGRect?
  ) -> CGFloat? {
    guard let itemIndex = itemIndexForPage(pageID) else { return nil }
    guard let frame = frameForItemIndex(itemIndex) else { return nil }
    return targetTopY(itemMinY: frame.minY, offsetWithinItem: offsetWithinPage)
  }

  private static func offsetWithinItem(currentTopY: CGFloat, itemMinY: CGFloat) -> CGFloat {
    currentTopY - itemMinY
  }

  private static func targetTopY(itemMinY: CGFloat, offsetWithinItem: CGFloat) -> CGFloat {
    itemMinY + offsetWithinItem
  }

  static func clampedY(_ value: CGFloat, min minY: CGFloat, max maxY: CGFloat) -> CGFloat {
    min(max(value, minY), maxY)
  }
}
