//
// NextBookToReadResolver.swift
//
//

import Foundation

/// Resolves the book to suggest after a book, in its series or in a read list,
/// by the rule the dashboard follows: the first later book that isn't read, or
/// the plain next book when every later one is read, so re-reading still moves
/// forward.
nonisolated enum NextBookToReadResolver {
  private static let unreadStatuses: [ReadStatus] = [.unread, .inProgress]

  @concurrent
  static func resolve(after book: Book, readListId: String?) async throws -> Book? {
    let firstUnread: Book?
    if let readListId {
      firstUnread = try await firstUnreadBook(inReadList: readListId, after: book.id)
    } else {
      firstUnread = try await firstUnreadBook(inSeriesAfter: book)
    }
    if let firstUnread {
      return firstUnread
    }
    return try await BookService.getNextBook(bookId: book.id, readListId: readListId)
  }

  /// The position filter includes its bound, so the current book itself can
  /// come back first and is skipped.
  private static func firstUnreadBook(inSeriesAfter book: Book) async throws -> Book? {
    let filters = BookSearchFilters(
      includeReadStatuses: unreadStatuses,
      seriesId: book.seriesId,
      numberSortFrom: book.metadata.numberSort
    )
    let search = BookSearch(condition: BookSearch.buildCondition(filters: filters))
    return try await BookService.getBooksList(
      search: search,
      size: 2,
      sort: ["metadata.numberSort,asc"]
    ).content.first { $0.id != book.id }
  }

  /// The list's unread books arrive in list order, so the first one past the
  /// current book's position is the answer, usually on the first page.
  private static func firstUnreadBook(
    inReadList readListId: String,
    after bookId: String
  ) async throws -> Book? {
    let bookIds = try await ReadListService.getReadList(id: readListId).bookIds
    guard let currentIndex = bookIds.firstIndex(of: bookId) else { return nil }
    let positions = Dictionary(
      bookIds.enumerated().map { ($0.element, $0.offset) },
      uniquingKeysWith: { first, _ in first }
    )

    var options = ReadListBookBrowseOptions()
    options.includeReadStatuses = Set(unreadStatuses)
    var page = 0
    while true {
      let result = try await ReadListService.getReadListBooks(
        readListId: readListId,
        page: page,
        size: 20,
        browseOpts: options
      )
      if let book = result.content.first(where: { (positions[$0.id] ?? -1) > currentIndex }) {
        return book
      }
      if result.last || result.content.isEmpty {
        return nil
      }
      page += 1
    }
  }
}
