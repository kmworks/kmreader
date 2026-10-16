import Foundation

struct NativeCoverDeckState {
  private(set) var slotItems: [ReaderViewItem?] = Array(repeating: nil, count: 3)
  private(set) var frontSlotIndex = 0
  private(set) var middleSlotIndex = 1
  private(set) var backSlotIndex = 2

  var slotCount: Int {
    slotItems.count
  }

  var currentItem: ReaderViewItem? {
    slotItems[frontSlotIndex]
  }

  var nextItem: ReaderViewItem? {
    slotItems[middleSlotIndex]
  }

  var previousItem: ReaderViewItem? {
    slotItems[backSlotIndex]
  }

  func item(at slotIndex: Int) -> ReaderViewItem? {
    guard slotItems.indices.contains(slotIndex) else { return nil }
    return slotItems[slotIndex]
  }

  mutating func reset() {
    slotItems = Array(repeating: nil, count: 3)
    frontSlotIndex = 0
    middleSlotIndex = 1
    backSlotIndex = 2
  }

  mutating func rebuild(around item: ReaderViewItem, viewModel: ReaderViewModel) {
    slotItems[frontSlotIndex] = item
    updateAdjacentSlots(around: item, viewModel: viewModel)
  }

  mutating func updateAdjacentSlots(around item: ReaderViewItem, viewModel: ReaderViewModel) {
    slotItems[middleSlotIndex] = viewModel.adjacentViewItem(from: item, offset: 1)
    slotItems[backSlotIndex] = viewModel.adjacentViewItem(from: item, offset: -1)
  }

  mutating func prepareTransitionTarget(_ targetItem: ReaderViewItem, direction: Int) {
    if direction == 1 {
      if slotItems[middleSlotIndex] != targetItem {
        if slotItems[backSlotIndex] == targetItem {
          swap(&middleSlotIndex, &backSlotIndex)
        } else {
          slotItems[middleSlotIndex] = targetItem
        }
      }
      return
    }

    if slotItems[backSlotIndex] != targetItem {
      if slotItems[middleSlotIndex] == targetItem {
        swap(&middleSlotIndex, &backSlotIndex)
      } else {
        slotItems[backSlotIndex] = targetItem
      }
    }
  }

  mutating func rotateAfterCommit(
    to targetItem: ReaderViewItem,
    direction: Int,
    viewModel: ReaderViewModel
  ) {
    let oldFront = frontSlotIndex
    let oldMiddle = middleSlotIndex
    let oldBack = backSlotIndex

    if direction == 1 {
      frontSlotIndex = oldMiddle
      middleSlotIndex = oldBack
      backSlotIndex = oldFront
    } else {
      frontSlotIndex = oldBack
      middleSlotIndex = oldFront
      backSlotIndex = oldMiddle
    }

    slotItems[frontSlotIndex] = targetItem
    updateAdjacentSlots(around: targetItem, viewModel: viewModel)
  }
}
