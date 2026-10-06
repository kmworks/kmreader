//
// SidebarLibraryItem.swift
//
//

import Foundation

nonisolated struct SidebarLibraryItem: Hashable, Identifiable, Sendable {
  let id: String
  let libraryId: String
  let name: String
  let fileSize: Double?
  let booksCount: Double?
  let seriesCount: Double?
  let sidecarsCount: Double?
  let collectionsCount: Double?
  let readlistsCount: Double?

  init(
    libraryId: String,
    name: String,
    fileSize: Double?,
    booksCount: Double?,
    seriesCount: Double?,
    sidecarsCount: Double?,
    collectionsCount: Double?,
    readlistsCount: Double?
  ) {
    id = libraryId
    self.libraryId = libraryId
    self.name = name
    self.fileSize = fileSize
    self.booksCount = booksCount
    self.seriesCount = seriesCount
    self.sidecarsCount = sidecarsCount
    self.collectionsCount = collectionsCount
    self.readlistsCount = readlistsCount
  }

  init(selection: LibrarySelection) {
    self.init(
      libraryId: selection.libraryId,
      name: selection.name,
      fileSize: selection.fileSize,
      booksCount: selection.booksCount,
      seriesCount: selection.seriesCount,
      sidecarsCount: selection.sidecarsCount,
      collectionsCount: selection.collectionsCount,
      readlistsCount: selection.readlistsCount
    )
  }

  var displayBookCount: Int? {
    booksCount.map { Int($0) }
  }

  /// Whether any admin metrics are present.
  var hasAnyMetrics: Bool {
    fileSize != nil || seriesCount != nil || booksCount != nil || sidecarsCount != nil
      || collectionsCount != nil || readlistsCount != nil
  }

  /// Client-side sum of per-library metrics; a field stays nil when no
  /// library reports it. For the full set prefer the server's all-libraries
  /// entry instead — overlapping library roots make sums overstate file size,
  /// and a list spanning libraries counts once per touched library.
  static func aggregating(_ items: [SidebarLibraryItem]) -> SidebarLibraryItem {
    func sum(_ keyPath: KeyPath<SidebarLibraryItem, Double?>) -> Double? {
      let values = items.compactMap { $0[keyPath: keyPath] }
      return values.isEmpty ? nil : values.reduce(0, +)
    }
    return SidebarLibraryItem(
      libraryId: "",
      name: "",
      fileSize: sum(\.fileSize),
      booksCount: sum(\.booksCount),
      seriesCount: sum(\.seriesCount),
      sidecarsCount: sum(\.sidecarsCount),
      collectionsCount: sum(\.collectionsCount),
      readlistsCount: sum(\.readlistsCount)
    )
  }
}
