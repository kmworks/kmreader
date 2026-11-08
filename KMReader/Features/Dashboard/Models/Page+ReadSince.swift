//
// Page+ReadSince.swift
//
//

import Foundation

extension Page where T == Book {
  /// Keeps the books read at or after `cutoff`, for a page sorted by read date,
  /// newest first: the first older book ends the list, since later pages can
  /// only hold older ones. A nil cutoff keeps the page as is.
  nonisolated func readSince(_ cutoff: Date?) -> Page<Book> {
    guard let cutoff else { return self }
    let kept = content.filter { book in
      guard let readDate = book.readProgress?.readDate else { return false }
      return readDate >= cutoff
    }
    guard kept.count < content.count else { return self }
    return Page(
      content: kept,
      pageable: pageable,
      totalElements: number * size + kept.count,
      totalPages: number + 1,
      last: true,
      size: size,
      number: number,
      numberOfElements: kept.count,
      first: first,
      empty: kept.isEmpty
    )
  }
}
