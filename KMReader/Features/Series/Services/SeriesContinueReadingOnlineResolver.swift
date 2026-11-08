//
// SeriesContinueReadingOnlineResolver.swift
//
//

import Foundation

nonisolated enum SeriesContinueReadingOnlineResolver {
  @concurrent
  static func resolve(seriesId: String) async -> Book? {
    if let inProgress = await fetchLatestBook(seriesId: seriesId, status: .inProgress) {
      return inProgress
    }

    if let lastRead = await fetchLatestBook(seriesId: seriesId, status: .read) {
      if let next = try? await BookService.getNextBook(bookId: lastRead.id) {
        return next
      }
      if let unread = await fetchFirstUnreadBook(seriesId: seriesId) {
        return unread
      }
      return lastRead
    }

    return await fetchFirstUnreadBook(seriesId: seriesId)
  }

  private static func fetchLatestBook(seriesId: String, status: ReadStatus) async -> Book? {
    var options = BookBrowseOptions()
    options.includeReadStatuses = [status]
    options.sortField = .dateRead
    options.sortDirection = .descending

    if let page = try? await BookService.getBooks(
      seriesId: seriesId,
      page: 0,
      size: 1,
      browseOpts: options
    ) {
      return page.content.first
    }

    return nil
  }

  private static func fetchFirstUnreadBook(seriesId: String) async -> Book? {
    var options = BookBrowseOptions()
    options.includeReadStatuses = [.unread]
    options.sortField = .series
    options.sortDirection = .ascending

    if let page = try? await BookService.getBooks(
      seriesId: seriesId,
      page: 0,
      size: 1,
      browseOpts: options
    ) {
      return page.content.first
    }

    return nil
  }
}
