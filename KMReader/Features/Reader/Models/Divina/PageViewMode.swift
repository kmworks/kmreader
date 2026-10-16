//
// PageViewMode.swift
//
//

enum PageViewMode {
  case comicSingle  // LTR horizontal single-page
  case mangaSingle  // RTL horizontal single-page
  case comicDual  // LTR horizontal dual-page
  case mangaDual  // RTL horizontal dual-page
  case vertical  // Vertical scrolling single-page

  init(direction: ReadingDirection, useDualPage: Bool) {
    switch direction {
    case .ltr:
      self = useDualPage ? .comicDual : .comicSingle
    case .rtl:
      self = useDualPage ? .mangaDual : .mangaSingle
    case .vertical, .webtoon:
      self = .vertical
    }
  }

  var isRTL: Bool {
    self == .mangaSingle || self == .mangaDual
  }

  var isDualPage: Bool {
    self == .comicDual || self == .mangaDual
  }

  var isVertical: Bool {
    self == .vertical
  }

  func displayOrderedItems(_ items: [ReaderViewItem]) -> [ReaderViewItem] {
    guard isRTL && !isVertical else { return items }
    return Array(items.reversed())
  }
}
