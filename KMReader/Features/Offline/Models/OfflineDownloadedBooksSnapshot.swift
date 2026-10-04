//
// OfflineDownloadedBooksSnapshot.swift
//
//

import Foundation

nonisolated struct OfflineDownloadedBookItem: Equatable, Identifiable, Sendable {
  let id: String
  let instanceId: String
  let bookId: String
  let seriesId: String
  let libraryId: String
  let bookName: String
  let seriesTitle: String
  let metaNumber: String
  let metaTitle: String
  let metaNumberSort: Double
  let downloadedSize: Int64
  let isReadCompleted: Bool

  var listTitle: String {
    "#\(metaNumber) - \(metaTitle)"
  }

  var oneshotTitle: String {
    metaTitle.isEmpty ? bookName : metaTitle
  }
}

nonisolated struct OfflineDownloadedSeriesGroup: Equatable, Identifiable, Sendable {
  let id: String
  let name: String?
  let books: [OfflineDownloadedBookItem]

  var downloadedBooksCount: Int {
    books.count
  }

  var downloadedSize: Int64 {
    books.reduce(0) { $0 + $1.downloadedSize }
  }
}

nonisolated struct OfflineDownloadedLibraryGroup: Equatable, Identifiable, Sendable {
  let id: String
  let name: String?
  let seriesGroups: [OfflineDownloadedSeriesGroup]
  let oneshotBooks: [OfflineDownloadedBookItem]

  var downloadedSize: Int64 {
    let seriesSize = seriesGroups.reduce(0) { $0 + $1.downloadedSize }
    let oneshotSize = oneshotBooks.reduce(0) { $0 + $1.downloadedSize }
    return seriesSize + oneshotSize
  }

  var downloadedBooksCount: Int {
    let seriesCount = seriesGroups.reduce(0) { $0 + $1.downloadedBooksCount }
    return seriesCount + oneshotBooks.count
  }
}

nonisolated struct OfflineDownloadedBooksSnapshot: Equatable, Sendable {
  let libraryGroups: [OfflineDownloadedLibraryGroup]

  static let empty = OfflineDownloadedBooksSnapshot(libraryGroups: [])

  var isEmpty: Bool {
    libraryGroups.allSatisfy { $0.seriesGroups.isEmpty && $0.oneshotBooks.isEmpty }
  }

  var totalDownloadedSize: Int64 {
    libraryGroups.reduce(0) { $0 + $1.downloadedSize }
  }

  var totalDownloadedBooksCount: Int {
    libraryGroups.reduce(0) { $0 + $1.downloadedBooksCount }
  }

  var hasReadBooks: Bool {
    libraryGroups.contains { libraryGroup in
      libraryGroup.oneshotBooks.contains { $0.isReadCompleted }
        || libraryGroup.seriesGroups.contains { seriesGroup in
          seriesGroup.books.contains { $0.isReadCompleted }
        }
    }
  }

  /// Snapshot without the given books (e.g. staged for deletion); empty groups drop out.
  func filtered(excludingBookIds: Set<String>) -> OfflineDownloadedBooksSnapshot {
    guard !excludingBookIds.isEmpty else { return self }
    let groups = libraryGroups.compactMap { libraryGroup -> OfflineDownloadedLibraryGroup? in
      let seriesGroups = libraryGroup.seriesGroups.compactMap {
        seriesGroup -> OfflineDownloadedSeriesGroup? in
        let books = seriesGroup.books.filter { !excludingBookIds.contains($0.bookId) }
        guard !books.isEmpty else { return nil }
        return OfflineDownloadedSeriesGroup(id: seriesGroup.id, name: seriesGroup.name, books: books)
      }
      let oneshotBooks = libraryGroup.oneshotBooks.filter { !excludingBookIds.contains($0.bookId) }
      guard !seriesGroups.isEmpty || !oneshotBooks.isEmpty else { return nil }
      return OfflineDownloadedLibraryGroup(
        id: libraryGroup.id, name: libraryGroup.name, seriesGroups: seriesGroups,
        oneshotBooks: oneshotBooks)
    }
    return OfflineDownloadedBooksSnapshot(libraryGroups: groups)
  }
}
