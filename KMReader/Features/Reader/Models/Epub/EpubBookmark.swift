//
// EpubBookmark.swift
//
//

import Foundation

/// A saved reading position inside one EPUB book.
///
/// The position is stored as a chapter index plus a fraction of that chapter so
/// the jump survives changes that re-paginate the book (viewport, font size,
/// rendering engine). `chapterFraction` sits at the centre of the saved page
/// rather than at its leading edge: restoring goes through
/// `EpubNavigationDestination.fraction`, which rounds down to a page index, and
/// a page-centre value cannot round down into the previous page.
nonisolated struct EpubBookmark: Identifiable, Codable, Equatable, Sendable {
  var id: UUID
  var instanceId: String
  var bookId: String
  var chapterIndex: Int
  var chapterHref: String
  var chapterFraction: Double
  /// Book-wide progress at capture time, for display only: chapter weights can
  /// be missing, so it is never used to restore the position.
  var totalProgression: Double
  var chapterTitle: String?
  var createdAt: Date

  init(
    id: UUID = UUID(),
    instanceId: String,
    bookId: String,
    chapterIndex: Int,
    chapterHref: String,
    chapterFraction: Double,
    totalProgression: Double,
    chapterTitle: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.instanceId = instanceId
    self.bookId = bookId
    self.chapterIndex = chapterIndex
    self.chapterHref = chapterHref
    self.chapterFraction = chapterFraction
    self.totalProgression = totalProgression
    self.chapterTitle = chapterTitle
    self.createdAt = createdAt
  }
}

nonisolated extension EpubBookmark {
  /// The page this bookmark lands on for a given chapter page count.
  ///
  /// Restoration goes through `EpubNavigationDestination.fraction`, which
  /// rounds the stored fraction down, so on-page comparisons use that same
  /// mapping instead of comparing raw fractions: the fraction gap between
  /// neighbouring pages shrinks as a chapter gains pages.
  func pageIndex(pageCount: Int) -> Int {
    guard pageCount > 0 else { return 0 }
    return max(0, min(pageCount - 1, Int((Double(pageCount) * chapterFraction).rounded(.down))))
  }
}
