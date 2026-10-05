//
// ProgressSyncService.swift
//
//

import Foundation
import OSLog

@globalActor
actor ProgressSyncService {
  static let shared = ProgressSyncService()

  private let logger = AppLogger(.sync)
  private var isSyncing = false
  private var idleWaiters: [CheckedContinuation<Void, Never>] = []

  private init() {}

  /// Replays offline-queued progress to the server. When a push is already in
  /// flight (e.g. the reconnect handler and the foreground handler fired
  /// together), waits for it instead of skipping, so every caller can treat
  /// the server state as converged once this returns and safely pull after.
  func syncPendingProgress(instanceId: String) async {
    logger.debug("🚀 Starting pending progress sync for instance \(instanceId)")

    if isSyncing {
      logger.info("⏳ Progress sync already in progress, waiting for it")
      await withCheckedContinuation { continuation in
        if isSyncing {
          idleWaiters.append(continuation)
        } else {
          continuation.resume()
        }
      }
      return
    }

    guard !AppConfig.isOffline else {
      logger.info("⏭️ Still offline, skipping progress sync")
      return
    }

    isSyncing = true
    defer {
      isSyncing = false
      let waiters = idleWaiters
      idleWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      logger.debug("🏁 Finished pending progress sync for instance \(instanceId)")
    }

    guard let database = await DatabaseOperator.databaseIfConfigured() else {
      logger.warning("⚠️ Skipping pending progress sync because database is not configured")
      return
    }

    let pending = await database.fetchPendingProgress(instanceId: instanceId)

    guard !pending.isEmpty else {
      logger.info("✅ No pending progress to sync")
      return
    }

    logger.info("🔄 Syncing \(pending.count) pending progress items")

    var successCount = 0
    var failureCount = 0
    var ignoredConflictCount = 0
    var ignoredNonRetryableCount = 0
    var skippedStaleCount = 0
    var completedBookIds = Set<String>()
    var staleSkippedBookIds = Set<String>()

    for item in pending {
      logger.debug(
        "🧾 Sync pending item id=\(item.id), book=\(item.bookId), page=\(item.page), completed=\(item.completed), hasProgressionData=\(item.progressionData != nil), createdAt=\(item.createdAt.ISO8601Format())"
      )
      do {
        let outcome = try await syncProgressItem(item)
        await database.deletePendingProgress(id: item.id)

        switch outcome {
        case .replayed:
          successCount += 1
          logger.debug("🧹 Removed synced pending item id=\(item.id)")
          if item.completed {
            completedBookIds.insert(item.bookId)
          }
        case .skippedStale:
          skippedStaleCount += 1
          logger.debug("🧹 Removed stale pending item id=\(item.id) without replaying to server")
          staleSkippedBookIds.insert(item.bookId)
        }
      } catch {
        if let apiError = error as? APIError {
          if apiError.isConflict {
            logger.info(
              "⏭️ Ignored progress conflict (409) for book \(item.bookId) (pending id=\(item.id))"
            )
            await database.deletePendingProgress(id: item.id)
            ignoredConflictCount += 1
            if item.completed {
              completedBookIds.insert(item.bookId)
            }
            continue
          }

          if let statusCode = apiError.statusCode, (400..<500).contains(statusCode), statusCode != 408,
            statusCode != 429
          {
            logger.info(
              "⏭️ Ignored non-retryable progress error (\(statusCode)) for book \(item.bookId) (pending id=\(item.id))"
            )
            await database.deletePendingProgress(id: item.id)
            ignoredNonRetryableCount += 1
            continue
          }
        }
        logger.error(
          "❌ Failed to sync progress for book \(item.bookId) (pending id=\(item.id)): \(error.localizedDescription)"
        )
        failureCount += 1
      }
    }

    // Batch sync books and series after individual progress items are processed.
    // Stale-skipped books are also refreshed so the local cache catches up to the
    // server's authoritative state (the local cache holds the offline-written value
    // from before the pending was discarded).
    var seriesIdsToRefresh = Set<String>()
    let booksToRefresh = completedBookIds.union(staleSkippedBookIds)
    for bookId in booksToRefresh {
      let isStaleSkip = staleSkippedBookIds.contains(bookId)
      logger.debug(
        "🔄 Refreshing book after progress sync: book=\(bookId), reason=\(isStaleSkip ? "stale-skip" : "completed")"
      )
      if let book = try? await SyncService.syncBook(bookId: bookId) {
        seriesIdsToRefresh.insert(book.seriesId)
      }
    }

    for seriesId in seriesIdsToRefresh {
      logger.debug("🔄 Refreshing series after progress sync: series=\(seriesId)")
      _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
    }

    if successCount > 0 {
      logger.info("✅ Successfully synced \(successCount) progress items")
      if failureCount == 0 {
        await ErrorManager.shared.notify(
          message: String(localized: "notification.progressSyncCompleted"))
      }
    }

    if ignoredConflictCount > 0 {
      logger.info("⏭️ Ignored \(ignoredConflictCount) progress conflicts (409)")
    }

    if ignoredNonRetryableCount > 0 {
      logger.info("⏭️ Ignored \(ignoredNonRetryableCount) non-retryable progress errors (4xx)")
    }

    if skippedStaleCount > 0 {
      logger.info(
        "⏭️ Skipped \(skippedStaleCount) stale pending items (server had a newer write than the queued pending)"
      )
    }

    if failureCount > 0 {
      logger.warning("⚠️ Failed to sync \(failureCount) progress items, will retry later")
      await ErrorManager.shared.notify(
        message: String(localized: "notification.progressSyncFailed"))
    }
  }

  private enum ProgressItemSyncOutcome {
    case replayed
    case skippedStale
  }

  /// Tolerance for client/server clock skew when comparing pending `createdAt` against
  /// server-side `readProgress.lastModified`. NTP-synced devices typically agree within
  /// a second; 60s is generous and avoids false positives without weakening the guard.
  private static let staleDetectionClockSkewTolerance: TimeInterval = 60

  private func syncProgressItem(_ item: PendingProgressSummary) async throws -> ProgressItemSyncOutcome {
    // Defensive guard against replaying a pending entry that the server has already
    // moved past via some other path (markAsRead from this device, completion via the
    // Komga web UI, completion on another client, etc.). If the server's read-progress
    // was last modified after this pending was queued, the pending is by definition
    // stale — replaying it would silently regress the server's state.
    //
    // This is the first conflict-resolution use of `lastModified` in the codebase. It
    // does not cover every regression path (notably: pending queued *after* a server
    // completion, where the lastModified is older than the pending's createdAt — that
    // case would need intent tracking that we don't have today).
    if let serverBook = try? await BookService.getBook(id: item.bookId),
      let serverProgress = serverBook.readProgress,
      serverProgress.lastModified
        > item.createdAt.addingTimeInterval(Self.staleDetectionClockSkewTolerance)
    {
      logger.info(
        "⏭️ Skipping stale pending for book \(item.bookId): server.lastModified=\(serverProgress.lastModified.ISO8601Format()) is newer than pending.createdAt=\(item.createdAt.ISO8601Format()) (+ \(Int(Self.staleDetectionClockSkewTolerance))s tolerance)"
      )

      // For EPUB pendings, also refresh the local `epubProgressionRaw` locator from
      // the server. The caller's post-loop `SyncService.syncBook` only refreshes the
      // Book DTO via `applyBook`, which does not touch `epubProgressionRaw` — that
      // field is written only by `updateBookEpubProgression`. Without this extra
      // fetch, the stale local locator would persist after a stale-skip and the
      // next EPUB resume would use it (especially when the user reopens the book
      // offline). Best-effort: failures here are logged but do not fail the skip.
      if item.progressionData != nil {
        do {
          let serverProgression = try await BookService.getWebPubProgression(
            bookId: item.bookId
          )
          if let database = try? await DatabaseOperator.database() {
            await database.updateBookEpubProgression(
              bookId: item.bookId,
              progression: serverProgression
            )
            logger.debug(
              "💾 Refreshed local EPUB progression from server after stale-skip: book=\(item.bookId)"
            )
          }
        } catch {
          logger.warning(
            "⚠️ Failed to refresh EPUB progression from server after stale-skip for book \(item.bookId): \(error.localizedDescription)"
          )
        }
      }

      return .skippedStale
    }

    // Check if this is EPUB progression or page-based progress
    if let progressionData = item.progressionData {
      logger.debug(
        "📤 Sync EPUB pending progression for book \(item.bookId), payloadBytes=\(progressionData.count)"
      )
      // EPUB progression - decode on MainActor
      let progression = try await MainActor.run {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R2Progression.self, from: progressionData)
      }

      try await BookService.updateWebPubProgression(
        bookId: item.bookId,
        progression: progression
      )
      try await DatabaseOperator.database().updateBookEpubProgression(
        bookId: item.bookId,
        progression: progression
      )
      logger.debug("✅ Synced EPUB progression for book \(item.bookId)")

    } else {
      logger.debug(
        "📤 Sync page pending progress for book \(item.bookId), page=\(item.page), completed=\(item.completed)"
      )
      // Page-based progress
      try await BookService.updatePageReadProgress(
        bookId: item.bookId,
        page: item.page,
        completed: item.completed
      )
      logger.debug("✅ Synced page progress for book \(item.bookId) - page \(item.page)")
    }

    return .replayed
  }
}
