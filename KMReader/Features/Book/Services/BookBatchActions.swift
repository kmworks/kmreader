//
// BookBatchActions.swift
//
//

import Foundation

@MainActor
enum BookBatchActions {
  static func mark(
    ids: [String],
    read: Bool,
    instanceId: String,
    seriesId: String? = nil,
    using controller: BatchOperationController
  ) async -> BatchOperationOutcome {
    let outcome = await controller.run(ids: ids) { bookId in
      if read {
        try await BookService.markAsRead(bookId: bookId)
      } else {
        try await BookService.markAsUnread(bookId: bookId)
      }
    }

    if !outcome.succeeded.isEmpty {
      if let seriesId {
        _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
        try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
        await ContentProjectionNotifier.postSeriesBooksDidChange(
          seriesId: seriesId,
          reason: .readingProgress
        )
      } else {
        await SyncService.syncVisitedItems(
          bookIds: Set(outcome.succeeded),
          seriesIds: await seriesIds(
            forBookIds: outcome.succeeded,
            instanceId: instanceId
          )
        )
        await ContentProjectionNotifier.postBooksAndSeriesDidChange(
          bookIds: outcome.succeeded,
          instanceId: instanceId,
          reason: .readingProgress
        )
      }
      await DashboardSectionRefreshNotifier.postReadStatusChanged(
        source: .manual,
        reason: "Books read status changed"
      )
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alertBatchFailure(
        failedCount: outcome.failed.count,
        totalCount: outcome.totalCount,
        error: firstError
      )
    } else if read {
      ErrorManager.shared.notify(message: String(localized: "notification.book.markedRead"))
    } else {
      ErrorManager.shared.notify(message: String(localized: "notification.book.markedUnread"))
    }

    return outcome
  }

  static func deleteFiles(
    ids: [String],
    instanceId: String,
    using controller: BatchOperationController
  ) async -> BatchOperationOutcome {
    let outcome = await controller.run(ids: ids) { bookId in
      try await BookDeletionService.deleteBook(bookId: bookId, instanceId: instanceId)
    }

    if !outcome.succeeded.isEmpty {
      await DashboardSectionRefreshNotifier.post(
        sections: DashboardSectionRefreshNotifier.bookContentSections
          .union(DashboardSectionRefreshNotifier.seriesContentSections),
        source: .manual,
        reason: "Book files batch deleted"
      )
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alertBatchFailure(
        failedCount: outcome.failed.count,
        totalCount: outcome.totalCount,
        error: firstError
      )
    } else {
      ErrorManager.shared.notify(
        message: String(localized: "batch.books.deleted \(outcome.succeeded.count)")
      )
    }

    return outcome
  }

  private static func seriesIds(forBookIds bookIds: [String], instanceId: String) async -> Set<String> {
    guard let database = try? await DatabaseOperator.database() else { return [] }
    var ids: Set<String> = []
    for bookId in bookIds {
      if let item = try? await database.fetchBookDisplayItem(
        bookId: bookId,
        instanceId: instanceId
      ) {
        ids.insert(item.book.seriesId)
      }
    }
    return ids
  }
}
