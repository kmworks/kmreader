//
// PageCurlViewItemsSnapshot.swift
//

import Foundation

struct PageCurlViewItemsSnapshot: Equatable {
  let items: [ReaderViewItem]

  private let indexByItem: [ReaderViewItem: Int]
  private let indexByPageID: [ReaderPageID: Int]

  init(items: [ReaderViewItem]) {
    self.items = items

    var itemIndices: [ReaderViewItem: Int] = [:]
    var pageIndices: [ReaderPageID: Int] = [:]
    for (index, item) in items.enumerated() {
      if itemIndices[item] == nil {
        itemIndices[item] = index
      }
      for pageID in item.pageIDs where pageIndices[pageID] == nil {
        pageIndices[pageID] = index
      }
    }
    self.indexByItem = itemIndices
    self.indexByPageID = pageIndices
  }

  var count: Int {
    items.count
  }

  var isEmpty: Bool {
    items.isEmpty
  }

  func item(at index: Int) -> ReaderViewItem? {
    guard items.indices.contains(index) else { return nil }
    return items[index]
  }

  func index(for item: ReaderViewItem) -> Int? {
    indexByItem[item]
  }

  func matchingItem(for anchor: ReaderPositionAnchor) -> ReaderViewItem? {
    if let item = anchor.item, indexByItem[item] != nil {
      return item
    }
    // A merged split (`.both`) cannot exact-match after a rebuild; honor the
    // committed split side before falling back to the first item for the page.
    let pageID = anchor.focusedPageID ?? anchor.item?.pageID
    if let pageID, let part = anchor.preferredSplitPart,
      let index = indexByItem[.split(id: pageID, part: part)]
    {
      return item(at: index)
    }
    if let focusedPageID = anchor.focusedPageID,
      let index = indexByPageID[focusedPageID]
    {
      return item(at: index)
    }
    if let pageID = anchor.item?.pageID,
      let index = indexByPageID[pageID]
    {
      return item(at: index)
    }
    return nil
  }

  func resolvedItem(for anchor: ReaderPositionAnchor) -> ReaderViewItem? {
    matchingItem(for: anchor) ?? items.first
  }

  func index(for anchor: ReaderPositionAnchor) -> Int? {
    guard let item = resolvedItem(for: anchor) else { return nil }
    return index(for: item)
  }
}
