//
// WebtoonContentItems.swift
//

import CoreGraphics
import Foundation

struct WebtoonContentItems {
  enum Item: Equatable {
    case page(ReaderPageID)
    case end(String)
  }

  let items: [Item]
  let itemIndexByPageID: [ReaderPageID: Int]

  static var empty: WebtoonContentItems {
    WebtoonContentItems(items: [], itemIndexByPageID: [:])
  }

  static func build(from viewModel: ReaderViewModel?) -> WebtoonContentItems {
    guard let viewModel else {
      return .empty
    }

    var items: [Item] = []
    var itemIndexByPageID: [ReaderPageID: Int] = [:]

    for segment in viewModel.segments {
      if !segment.pages.isEmpty {
        for page in segment.pages {
          let pageID = ReaderPageID(bookId: segment.currentBook.id, pageNumber: page.number)
          itemIndexByPageID[pageID] = items.count
          items.append(.page(pageID))
        }
      }
      items.append(.end(segment.currentBook.id))
    }

    return WebtoonContentItems(items: items, itemIndexByPageID: itemIndexByPageID)
  }

  static func lastVisibleItemIndex(
    itemCount: Int,
    viewportBottom: CGFloat,
    threshold: CGFloat,
    visibleItemIndices: [Int],
    frameForItemAtIndex: (Int) -> CGRect?
  ) -> Int {
    let sortedVisibleIndices =
      visibleItemIndices
      .filter { $0 >= 0 && $0 < itemCount }
      .sorted()

    guard let firstVisibleIndex = sortedVisibleIndices.first else {
      return lastVisibleItemIndex(
        itemCount: itemCount,
        viewportBottom: viewportBottom,
        threshold: threshold,
        frameForItemAtIndex: frameForItemAtIndex
      )
    }

    var candidateIndex = firstVisibleIndex
    for itemIndex in sortedVisibleIndices {
      guard let frame = frameForItemAtIndex(itemIndex) else {
        continue
      }
      if frame.maxY <= viewportBottom + threshold {
        candidateIndex = itemIndex
      } else {
        break
      }
    }

    return candidateIndex
  }

  static func lastVisibleItemIndex(
    itemCount: Int,
    viewportBottom: CGFloat,
    threshold: CGFloat,
    frameForItemAtIndex: (Int) -> CGRect?
  ) -> Int {
    var visibleIndex = 0
    for itemIndex in 0..<itemCount {
      guard let frame = frameForItemAtIndex(itemIndex) else {
        continue
      }
      if frame.maxY <= viewportBottom + threshold {
        visibleIndex = itemIndex
      } else {
        break
      }
    }
    return visibleIndex
  }

}
