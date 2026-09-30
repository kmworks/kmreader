//
// NextBookToReadResolver.swift
//
//

import Foundation

/// Resolves the book to suggest after a book, in its series or in a read list.
/// With "Suggest Next Unread Book" on, that's the first later book that isn't
/// read, like the dashboard, else the plain next book, so re-reading still
/// moves forward. With it off, the plain next book.
nonisolated enum NextBookToReadResolver {
  /// One `/next` request that asks the server to skip read books. Servers
  /// without `skipRead` return the plain next book; when that book is read,
  /// the local copy supplies the first unread book after it, if it knows one.
  @concurrent
  static func resolve(after bookId: String, readListId: String?, instanceId: String) async throws -> Book? {
    guard AppConfig.suggestNextUnreadBook else {
      return try await BookService.getNextBook(bookId: bookId, readListId: readListId)
    }
    guard
      let next = try await BookService.getNextBook(
        bookId: bookId,
        readListId: readListId,
        skipRead: true
      )
    else { return nil }
    guard next.isCompleted, let database = await DatabaseOperator.databaseIfConfigured() else {
      return next
    }
    return await database.getNextUnreadBook(
      instanceId: instanceId,
      bookId: bookId,
      readListId: readListId,
      readBookId: next.id
    ) ?? next
  }

  /// The same rule from the local copy alone, for offline reading.
  static func resolveLocally(
    after bookId: String,
    readListId: String?,
    instanceId: String,
    database: DatabaseOperator
  ) async -> Book? {
    await database.getNextBook(
      instanceId: instanceId,
      bookId: bookId,
      readListId: readListId,
      skipRead: AppConfig.suggestNextUnreadBook
    )
  }
}
