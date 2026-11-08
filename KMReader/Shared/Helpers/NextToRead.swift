//
// NextToRead.swift
//
//

import Foundation

extension Collection {
  /// The element to read after the one at `index`, in reading order: the
  /// first later element that isn't read, or the one right after `index` when
  /// every later element is read, so re-reading still moves forward.
  nonisolated func nextToRead(after index: Index, isRead: (Element) -> Bool) -> Element? {
    let later = self[self.index(after: index)...]
    return later.first(where: { !isRead($0) }) ?? later.first
  }
}
