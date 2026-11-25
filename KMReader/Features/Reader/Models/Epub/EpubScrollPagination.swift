import Foundation

/// Logical pages are evenly spaced over the scrollable range, including both ends.
nonisolated struct EpubScrollPagination {
  let contentHeight: CGFloat
  let viewportHeight: CGFloat

  var pageCount: Int {
    max(1, Int(ceil(max(contentHeight, 1) / max(viewportHeight, 1))))
  }

  var maximumOffset: CGFloat {
    max(0, contentHeight - max(viewportHeight, 1))
  }

  func offset(for pageIndex: Int) -> CGFloat {
    guard pageCount > 1 else { return 0 }
    let index = max(0, min(pageCount - 1, pageIndex))
    return maximumOffset * CGFloat(index) / CGFloat(pageCount - 1)
  }

  func pageIndex(at offset: CGFloat) -> Int {
    guard maximumOffset > 0 else { return 0 }
    let fraction = min(max(offset / maximumOffset, 0), 1)
    return Int((fraction * CGFloat(pageCount - 1)).rounded())
  }
}
