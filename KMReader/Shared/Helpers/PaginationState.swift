//
// PaginationState.swift
//
//

import Foundation

struct PaginationState<Item: Identifiable & Equatable> {
  let pageSize: Int
  var currentPage: Int = 0
  var hasMorePages: Bool = true
  var loadID: UUID = UUID()
  var items: [Item] = []

  init(pageSize: Int, items: [Item] = []) {
    self.pageSize = pageSize
    self.items = items
  }

  mutating func reset() {
    currentPage = 0
    hasMorePages = true
    loadID = UUID()
  }

  mutating func advance(moreAvailable: Bool) {
    hasMorePages = moreAvailable
    currentPage += 1
  }

  var isEmpty: Bool {
    items.isEmpty
  }

  func isLast(_ item: Item) -> Bool {
    items.last == item
  }

  func shouldLoadMore(after item: Item, threshold: Int = 3) -> Bool {
    guard threshold > 0 else { return isLast(item) }
    return items.suffix(threshold).contains(item)
  }

  mutating func applyPage(_ newItems: [Item]) -> Bool {
    if currentPage == 0 {
      guard newItems != items else { return false }
      items = newItems
    } else {
      // The server stream can shift between page fetches, and duplicate ids break ForEach.
      let loaded = Set(items.map(\.id))
      let uniqueItems = newItems.filter { !loaded.contains($0.id) }
      guard !uniqueItems.isEmpty else { return false }
      items.append(contentsOf: uniqueItems)
    }
    return true
  }

  /// Replaces the loaded window after revalidating already-loaded pages.
  /// Keeps currentPage and loadID so the list does not collapse back to
  /// the first page and the scroll position is preserved.
  mutating func replaceItems(_ newItems: [Item], moreAvailable: Bool) -> Bool {
    hasMorePages = moreAvailable
    guard newItems != items else { return false }
    items = newItems
    return true
  }

  mutating func removeItems(withIDs ids: Set<Item.ID>) -> Bool {
    guard !ids.isEmpty else { return false }
    let originalCount = items.count
    items.removeAll { ids.contains($0.id) }
    return items.count != originalCount
  }

}
