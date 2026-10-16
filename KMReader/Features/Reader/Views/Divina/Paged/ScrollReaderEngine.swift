//
// ScrollReaderEngine.swift
//
//

import Foundation

@MainActor
final class ScrollReaderEngine {
  private(set) var renderedItems: [ReaderViewItem] = []
  private(set) var committedItem: ReaderViewItem?
  private(set) var hasSyncedInitialPosition = false
  private(set) var isUserInteracting = false
  private(set) var isProgrammaticScrolling = false

  private var pendingInitialAnchor: ReaderPositionAnchor?
  private var pendingRenderedItems: [ReaderViewItem]?
  private var deferredAnchorItem: ReaderViewItem?
  private var pendingProgrammaticCommitItem: ReaderViewItem?

  var isInteractionActive: Bool {
    isUserInteracting || isProgrammaticScrolling
  }

  var hasPendingProgrammaticCommit: Bool {
    pendingProgrammaticCommitItem != nil
  }

  var programmaticTargetItem: ReaderViewItem? {
    resolveItem(pendingProgrammaticCommitItem)
  }

  func teardown() {
    pendingInitialAnchor = nil
    pendingRenderedItems = nil
    deferredAnchorItem = nil
    pendingProgrammaticCommitItem = nil
    renderedItems.removeAll()
    committedItem = nil
    hasSyncedInitialPosition = false
    isUserInteracting = false
    isProgrammaticScrolling = false
  }

  func installInitialItemsIfNeeded(_ items: [ReaderViewItem]) -> Bool {
    guard renderedItems.isEmpty else { return false }
    replaceRenderedItems(items)
    return true
  }

  func replaceRenderedItems(_ items: [ReaderViewItem]) {
    renderedItems = items
    pendingInitialAnchor = resolveAnchor(pendingInitialAnchor, in: items)
    pendingProgrammaticCommitItem = resolveItem(pendingProgrammaticCommitItem, in: items)
    committedItem = resolveItem(committedItem, in: items)
  }

  func queueRenderedItems(_ items: [ReaderViewItem], anchor: ReaderViewItem?) {
    pendingRenderedItems = items
    deferredAnchorItem =
      resolveItem(pendingProgrammaticCommitItem, in: items)
      ?? resolveItem(anchor, in: items)
  }

  func consumeQueuedRenderedItems(
    anchorFallback: ReaderViewItem?,
    preferAnchorFallback: Bool = false
  ) -> (
    items: [ReaderViewItem], anchor: ReaderViewItem?
  )? {
    guard let pendingRenderedItems else { return nil }
    self.pendingRenderedItems = nil
    let resolvedFallback = resolveItem(anchorFallback, in: pendingRenderedItems)
    let anchor =
      preferAnchorFallback
      ? resolvedFallback ?? deferredAnchorItem
      : deferredAnchorItem ?? resolvedFallback
    deferredAnchorItem = nil
    replaceRenderedItems(pendingRenderedItems)
    return (pendingRenderedItems, anchor)
  }

  func prepareInitialPosition(anchor: ReaderPositionAnchor?) -> ReaderViewItem? {
    guard !hasSyncedInitialPosition else { return nil }
    if let pendingInitialAnchor {
      return resolveAnchorItem(pendingInitialAnchor)
    }
    guard let anchor else { return nil }
    let resolvedAnchor = resolveAnchor(anchor)
    pendingInitialAnchor = resolvedAnchor
    return resolvedAnchor?.item
  }

  func setPendingInitialAnchor(_ anchor: ReaderPositionAnchor?) {
    pendingInitialAnchor = anchor.flatMap { resolveAnchor($0) }
  }

  func completeInitialPosition() -> ReaderViewItem? {
    guard !hasSyncedInitialPosition else { return nil }
    guard let anchor = pendingInitialAnchor, let item = resolveAnchorItem(anchor) else { return nil }
    pendingInitialAnchor = nil
    committedItem = item
    hasSyncedInitialPosition = true
    return item
  }

  func resolveItem(_ item: ReaderViewItem?) -> ReaderViewItem? {
    resolveItem(item, in: renderedItems)
  }

  func beginUserInteraction() -> Bool {
    guard !isUserInteracting else { return false }
    isUserInteracting = true
    return true
  }

  func endUserInteraction() -> Bool {
    guard isUserInteracting else { return false }
    isUserInteracting = false
    return true
  }

  func beginProgrammaticScroll(to item: ReaderViewItem) {
    isProgrammaticScrolling = true
    pendingProgrammaticCommitItem = resolveItem(item)
  }

  func endProgrammaticScroll() -> Bool {
    guard isProgrammaticScrolling else { return false }
    isProgrammaticScrolling = false
    return true
  }

  func consumePendingProgrammaticCommit() -> ReaderViewItem? {
    guard let pendingProgrammaticCommitItem else { return nil }
    self.pendingProgrammaticCommitItem = nil
    return resolveItem(pendingProgrammaticCommitItem)
  }

  func clearPendingProgrammaticCommit() {
    pendingProgrammaticCommitItem = nil
  }

  func cancelProgrammaticScroll() {
    isProgrammaticScrolling = false
    pendingProgrammaticCommitItem = nil
  }

  func isPendingProgrammaticCommit(_ item: ReaderViewItem) -> Bool {
    resolveItem(item) == pendingProgrammaticCommitItem
  }

  func commit(_ item: ReaderViewItem) {
    committedItem = resolveItem(item)
  }

  private func resolveItem(
    _ item: ReaderViewItem?,
    in snapshot: [ReaderViewItem]
  ) -> ReaderViewItem? {
    guard let item else { return nil }

    if snapshot.contains(item) {
      return item
    }

    // Match by any contained page so a page that became the second half of a
    // dual pair still resolves. Restoration must stay strict: an unresolvable
    // anchor is discarded instead of falling back to a positional item, which
    // in display order can be another segment's `.end` transition.
    return snapshot.first(where: { $0.pageIDs.contains(item.pageID) })
  }

  /// Re-resolves a pending initial anchor against a rebuilt snapshot. The item
  /// identity is refreshed but the anchor's focused page and split side travel
  /// with it, so a `.dual` pair (whose bare `pageID` is the pair's first page)
  /// or a merged `.both` split still restores to the committed page/half.
  private func resolveAnchor(
    _ anchor: ReaderPositionAnchor?,
    in snapshot: [ReaderViewItem]
  ) -> ReaderPositionAnchor? {
    guard let anchor, let item = resolveAnchorItem(anchor, in: snapshot) else { return nil }
    return ReaderPositionAnchor(
      item: item,
      focusedPageID: anchor.focusedPageID,
      preferredSplitPart: item.preferredSplitPart(preserving: anchor)
    )
  }

  private func resolveAnchorItem(
    _ anchor: ReaderPositionAnchor,
    in snapshot: [ReaderViewItem]
  ) -> ReaderViewItem? {
    if let item = anchor.item, snapshot.contains(item) {
      return item
    }
    // A remembered split side outranks page-level fallbacks so a wide page
    // merged into `.both` restores to the same half after the rebuild.
    let anchorPageID = anchor.focusedPageID ?? anchor.item?.pageID
    if let anchorPageID, let part = anchor.preferredSplitPart, part != .both {
      let splitItem = ReaderViewItem.split(id: anchorPageID, part: part)
      if snapshot.contains(splitItem) {
        return splitItem
      }
    }
    // Match by the focused page first: for a dual pair the focused page can be
    // the pair's second page, which the bare `item.pageID` fallback would miss.
    if let focusedPageID = anchor.focusedPageID,
      let match = snapshot.first(where: { $0.pageIDs.contains(focusedPageID) })
    {
      return match
    }
    if let item = anchor.item {
      return snapshot.first(where: { $0.pageIDs.contains(item.pageID) })
    }
    return nil
  }

  private func resolveAnchor(_ anchor: ReaderPositionAnchor?) -> ReaderPositionAnchor? {
    resolveAnchor(anchor, in: renderedItems)
  }

  private func resolveAnchorItem(_ anchor: ReaderPositionAnchor) -> ReaderViewItem? {
    resolveAnchorItem(anchor, in: renderedItems)
  }
}
