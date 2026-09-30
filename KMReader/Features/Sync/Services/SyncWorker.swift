//
// SyncWorker.swift
//
//

import Foundation

actor SyncWorker {
  private let logger = AppLogger(.sync)
  private let syncPageSize = 1000
  private let recentlyReadInitialPageSize = 200
  private let recentlyReadIncrementalPageSize = 20

  func sync(
    request: SyncRequest,
    onProgress: @escaping SyncProgressHandler
  ) async -> SyncResult {
    var hasFailures = false

    do {
      let database = try await DatabaseOperator.database()
      let storedLastSyncedAt = await database.getLastSyncedAt(instanceId: request.instanceId)
      let lastSyncedAt: (series: Date, books: Date) =
        request.forceFullSync
        ? (Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 0))
        : storedLastSyncedAt
      let syncStartTime = Date()

      logger.info(
        "🔄 Starting sync for instance: \(request.instanceId), forceFullSync: \(request.forceFullSync), seriesLastSynced: \(storedLastSyncedAt.series), booksLastSynced: \(storedLastSyncedAt.books)"
      )

      if !(await syncLibraries(
        instanceId: request.instanceId,
        database: database,
        onProgress: onProgress
      )) {
        hasFailures = true
      }

      if !(await syncAllCollections(
        instanceId: request.instanceId,
        database: database,
        onProgress: onProgress
      )) {
        hasFailures = true
      }

      var seriesSyncSucceeded = await syncSeriesIncremental(
        instanceId: request.instanceId,
        since: lastSyncedAt.series,
        database: database,
        onProgress: onProgress
      )
      if seriesSyncSucceeded && request.forceFullSync {
        seriesSyncSucceeded = await reconcileSeriesDeletions(
          instanceId: request.instanceId,
          database: database,
          onProgress: onProgress
        )
      }
      if !seriesSyncSucceeded {
        hasFailures = true
      } else {
        do {
          try await database.updateSeriesLastSyncedAt(
            instanceId: request.instanceId,
            date: syncStartTime
          )
        } catch {
          hasFailures = true
          logger.error("❌ Failed to update series lastSyncedAt: \(error)")
        }
      }

      if !(await syncAllReadLists(
        instanceId: request.instanceId,
        database: database,
        onProgress: onProgress
      )) {
        hasFailures = true
      }

      var booksSyncSucceeded = await syncBooksIncremental(
        instanceId: request.instanceId,
        since: lastSyncedAt.books,
        database: database,
        onProgress: onProgress
      )
      if booksSyncSucceeded && request.forceFullSync {
        booksSyncSucceeded = await reconcileBookDeletions(
          instanceId: request.instanceId,
          database: database,
          onProgress: onProgress
        )
      }
      if !booksSyncSucceeded {
        hasFailures = true
      } else {
        do {
          try await database.updateBooksLastSyncedAt(
            instanceId: request.instanceId,
            date: syncStartTime
          )
        } catch {
          hasFailures = true
          logger.error("❌ Failed to update books lastSyncedAt: \(error)")
        }
      }

      let readingProgressSynced = await syncReadingProgress(instanceId: request.instanceId)

      if hasFailures {
        logger.warning("⚠️ Sync completed with errors for instance: \(request.instanceId)")
      } else {
        logger.info("✅ Sync completed for instance: \(request.instanceId)")
      }

      return SyncResult(
        hasFailures: hasFailures,
        readingProgressSynced: readingProgressSynced
      )
    } catch {
      logger.error("❌ Failed to load sync markers: \(error)")
      return SyncResult(hasFailures: true, readingProgressSynced: false)
    }
  }

  func syncReadingProgress(instanceId: String) async -> Bool {
    guard !instanceId.isEmpty else { return false }
    guard let database = await DatabaseOperator.databaseIfConfigured() else {
      logger.error("❌ Failed to get database operator for reading progress sync")
      return false
    }

    let marker = AppConfig.recentlyReadRecordTime(instanceId: instanceId)
    // Incremental pulls run on a 30s foreground debounce, so keep the page
    // small; the marker scan paginates when more changed. The initial pull
    // (no marker) fetches a single larger page of recently-read books.
    let pageSize = marker == nil ? recentlyReadInitialPageSize : recentlyReadIncrementalPageSize
    var page = 0
    var shouldContinue = true
    var latestServerReadDate = marker
    var syncedCount = 0
    var syncedBookIds: [String] = []

    do {
      while shouldContinue {
        let result = try await BookService.getBooksList(
          search: BookSearch(condition: nil),
          page: page,
          size: pageSize,
          sort: ["readProgress.readDate,desc"]
        )

        let books = result.content
        guard !books.isEmpty else { break }

        if let newestInPage = books.compactMap({ $0.readProgress?.readDate }).max() {
          if let currentLatest = latestServerReadDate {
            latestServerReadDate = max(currentLatest, newestInPage)
          } else {
            latestServerReadDate = newestInPage
          }
        }

        let booksToSync: [Book]
        if let marker {
          booksToSync = books.filter { book in
            guard let readDate = book.readProgress?.readDate else { return false }
            return readDate > marker
          }
          let reachedMarker = books.contains { book in
            guard let readDate = book.readProgress?.readDate else { return true }
            return readDate <= marker
          }
          shouldContinue = !result.last && !reachedMarker
        } else {
          booksToSync = books.filter { $0.readProgress?.readDate != nil }
          shouldContinue = false
        }

        if !booksToSync.isEmpty {
          await database.upsertReadingProgressBooks(
            booksToSync,
            instanceId: instanceId
          )
          syncedCount += booksToSync.count
          syncedBookIds.append(contentsOf: booksToSync.map { $0.id })
          await refreshDownloadedEpubProgressions(
            books: booksToSync,
            instanceId: instanceId,
            database: database
          )
        }

        page += 1
      }

      if let latestServerReadDate {
        AppConfig.setRecentlyReadRecordTime(latestServerReadDate, instanceId: instanceId)
      }

      // Notify so dashboard cover badges and any BookQueryItemView reload the
      // freshly-pulled progress. Without this, the incremental upsert updates the
      // GRDB cache but the already-rendered cards (which reload on
      // `.bookProjectionDidChange`, not via live DB observation) keep showing
      // stale progress until the book is opened.
      if !syncedBookIds.isEmpty {
        await ContentProjectionNotifier.postBooksDidChange(
          bookIds: syncedBookIds,
          reason: .readingProgress
        )
      }

      logger.debug(
        "📘 Synced latest recently-read progress: count=\(syncedCount), marker=\(String(describing: latestServerReadDate))"
      )
      return true
    } catch {
      logger.warning("⚠️ Failed to sync latest recently-read progress: \(error)")
      return false
    }
  }

  /// Tolerates clock skew between the server-side readProgress.lastModified
  /// and the client-supplied locator `modified` timestamp, so a locator this
  /// device just uploaded is not immediately re-fetched.
  private let epubProgressionSkewTolerance: TimeInterval = 60

  /// Refreshes cached Readium locators for downloaded, in-progress EPUBs whose
  /// server-side read progress changed. Batch book endpoints only expose
  /// page-based progress, so the locator stored in `epubProgressionRaw` must
  /// be re-fetched per book here; otherwise reopening the book offline resumes
  /// from a stale position.
  private func refreshDownloadedEpubProgressions(
    books: [Book],
    instanceId: String,
    database: DatabaseOperator
  ) async {
    let inProgress = books.filter { $0.isInProgress }
    guard !inProgress.isEmpty else { return }

    let checkpoints = await database.fetchDownloadedEpubProgressionModifiedDates(
      instanceId: instanceId,
      bookIds: inProgress.map(\.id)
    )
    guard !checkpoints.isEmpty else { return }

    let lastModifiedByBookId = Dictionary(
      uniqueKeysWithValues: inProgress.compactMap { book in
        book.readProgress.map { (book.id, $0.lastModified) }
      }
    )
    let pageByBookId = Dictionary(
      uniqueKeysWithValues: inProgress.compactMap { book in
        book.readProgress.map { (book.id, $0.page) }
      }
    )

    var refreshedCount = 0
    for checkpoint in checkpoints {
      guard let serverLastModified = lastModifiedByBookId[checkpoint.bookId] else { continue }
      if let localModified = checkpoint.progressionModified,
        serverLastModified <= localModified.addingTimeInterval(epubProgressionSkewTolerance)
      {
        continue
      }

      switch await BookService.fetchRemoteWebPubProgression(bookId: checkpoint.bookId) {
      case .available(let progression):
        await database.updateBookEpubProgression(
          bookId: checkpoint.bookId,
          progression: progression
        )
        refreshedCount += 1
      case .missing:
        // A missing locator with a non-zero page means the server stores
        // page-based progress (KOReader/Kindle sync, paged readers, web UI);
        // map the page to a locator so offline resume can use it.
        let page = pageByBookId[checkpoint.bookId] ?? 0
        if page > 0,
          let progression = await EpubPageProgressionMapper.progression(
            bookId: checkpoint.bookId,
            page: page
          )
        {
          await database.updateBookEpubProgression(
            bookId: checkpoint.bookId,
            progression: progression
          )
          refreshedCount += 1
        } else if checkpoint.progressionModified == nil {
          // Never downgrade a locally cached locator on a missing-shaped
          // response; only record "missing" when there is no local position.
          await database.updateBookEpubProgression(
            bookId: checkpoint.bookId,
            progression: nil
          )
        }
      case .retryableFailure(let error):
        logger.warning(
          "⚠️ Failed to refresh EPUB progression for book \(checkpoint.bookId): \(error.localizedDescription)"
        )
      case .invalidPayload(let error):
        logger.warning(
          "⚠️ Ignoring non-retryable EPUB progression payload for book \(checkpoint.bookId): \(error.localizedDescription)"
        )
      }
    }

    if refreshedCount > 0 {
      logger.info("📖 Refreshed EPUB progression for \(refreshedCount) downloaded books")
    }
  }

  private func syncLibraries(
    instanceId: String,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(.libraries, progress: 0.0, onProgress: onProgress)
    do {
      let libraries = try await LibraryService.getLibraries()
      let libraryInfos = libraries.map { LibraryInfo(id: $0.id, name: $0.name) }
      try await database.replaceLibraries(libraryInfos, for: instanceId)
      await SyncService.postSidebarProjectionDidChange(instanceId: instanceId)
      logger.info("📚 Synced \(libraries.count) libraries")
      await report(.libraries, progress: 1.0, onProgress: onProgress)
      return true
    } catch {
      logger.error("❌ Failed to sync libraries: \(error)")
      await report(.libraries, progress: 1.0, onProgress: onProgress)
      return false
    }
  }

  private func syncAllCollections(
    instanceId: String,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(.collections, progress: 0.0, onProgress: onProgress)
    do {
      var page = 0
      var hasMore = true
      var totalPages = 1
      var remoteCollectionIds = Set<String>()

      while hasMore {
        let result: Page<SeriesCollection> = try await CollectionService.getCollections(
          page: page,
          size: syncPageSize
        )
        remoteCollectionIds.formUnion(result.content.map(\.id))
        await database.upsertCollections(result.content, instanceId: instanceId)

        totalPages = max(result.totalPages, 1)
        hasMore = !result.last
        page += 1

        await report(
          .collections,
          progress: Double(page) / Double(totalPages),
          onProgress: onProgress
        )
      }

      let deletedCollectionIds = await database.deleteCollectionsNotIn(
        remoteCollectionIds,
        instanceId: instanceId
      )
      await ContentProjectionNotifier.postCollectionsDidChange(collectionIds: deletedCollectionIds)
      if !deletedCollectionIds.isEmpty {
        logger.info("🧹 Removed \(deletedCollectionIds.count) stale collections")
      }
      await SyncService.postSidebarProjectionDidChange(instanceId: instanceId)
      logger.info("📂 Synced collections")
      return true
    } catch {
      logger.error("❌ Failed to sync collections: \(error)")
      await report(.collections, progress: 1.0, onProgress: onProgress)
      return false
    }
  }

  private func syncSeriesIncremental(
    instanceId: String,
    since: Date,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(
      .series,
      progress: 0.0,
      stage: .seriesIncremental,
      onProgress: onProgress
    )
    do {
      var page = 0
      var shouldContinue = true

      while shouldContinue {
        let result = try await SeriesService.getSeriesList(
          search: SeriesSearch(condition: nil),
          page: page,
          size: syncPageSize,
          sort: "lastModified,desc"
        )

        var itemsToSync: [Series] = []
        for series in result.content {
          if series.lastModified > since {
            itemsToSync.append(series)
          } else {
            shouldContinue = false
            break
          }
        }

        if !itemsToSync.isEmpty {
          await database.upsertSeriesList(itemsToSync, instanceId: instanceId)
        }

        page += 1
        if result.last {
          shouldContinue = false
        }

        await report(
          .series,
          progress: incrementalProgress(
            processedPages: page,
            totalPages: result.totalPages,
            finished: !shouldContinue
          ),
          stage: .seriesIncremental,
          onProgress: onProgress
        )
      }
      logger.info("📚 Synced series incrementally")
      return true
    } catch {
      logger.error("❌ Failed to sync series: \(error)")
      await report(
        .series,
        progress: 1.0,
        stage: .seriesIncremental,
        onProgress: onProgress
      )
      return false
    }
  }

  private func reconcileSeriesDeletions(
    instanceId: String,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(
      .series,
      progress: 0.0,
      stage: .seriesReconcile,
      onProgress: onProgress
    )
    do {
      let localCount = await database.fetchTotalSeriesCount(instanceId: instanceId)
      do {
        let remoteCount = try await fetchRemoteSeriesCountForDeletionReconcile()
        if localCount <= remoteCount {
          logger.debug(
            "⏭️ Skipped series reconcile: localCount=\(localCount), remoteCount=\(remoteCount)"
          )
          await report(
            .series,
            progress: 1.0,
            stage: .seriesReconcile,
            onProgress: onProgress
          )
          return true
        }
      } catch {
        logger.warning(
          "⚠️ Failed to preflight series reconcile counts, fallback to full scan: \(error)"
        )
      }

      let remoteSeriesIds = try await fetchAllSeriesIdsForDeletionReconcile(
        onProgress: onProgress
      )
      let deletedCount = await database.deleteSeriesNotIn(
        remoteSeriesIds,
        instanceId: instanceId
      )
      if deletedCount > 0 {
        logger.info("🧹 Removed \(deletedCount) stale series")
      }
      return true
    } catch {
      logger.error("❌ Failed to reconcile stale series: \(error)")
      return false
    }
  }

  private func syncAllReadLists(
    instanceId: String,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(.readLists, progress: 0.0, onProgress: onProgress)
    do {
      var page = 0
      var hasMore = true
      var totalPages = 1
      var remoteReadListIds = Set<String>()
      var automaticPolicyReadListIds = Set<String>()

      while hasMore {
        let result: Page<ReadList> = try await ReadListService.getReadLists(
          page: page,
          size: syncPageSize
        )
        remoteReadListIds.formUnion(result.content.map(\.id))
        let pagePolicyReadListIds = await database.upsertReadLists(result.content, instanceId: instanceId)
        automaticPolicyReadListIds.formUnion(pagePolicyReadListIds)

        totalPages = max(result.totalPages, 1)
        hasMore = !result.last
        page += 1

        await report(
          .readLists,
          progress: Double(page) / Double(totalPages),
          onProgress: onProgress
        )
      }

      await SyncService.syncAutomaticReadListBooks(Array(automaticPolicyReadListIds), instanceId: instanceId)
      let deletedReadListIds = await database.deleteReadListsNotIn(
        remoteReadListIds,
        instanceId: instanceId
      )
      await ContentProjectionNotifier.postReadListsDidChange(readListIds: deletedReadListIds)
      if !deletedReadListIds.isEmpty {
        logger.info("🧹 Removed \(deletedReadListIds.count) stale read lists")
      }
      await SyncService.postSidebarProjectionDidChange(instanceId: instanceId)
      logger.info("📖 Synced read lists")
      return true
    } catch {
      logger.error("❌ Failed to sync read lists: \(error)")
      await report(.readLists, progress: 1.0, onProgress: onProgress)
      return false
    }
  }

  private func syncBooksIncremental(
    instanceId: String,
    since: Date,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(
      .books,
      progress: 0.0,
      stage: .booksIncremental,
      onProgress: onProgress
    )
    do {
      var page = 0
      var shouldContinue = true

      while shouldContinue {
        let result = try await BookService.getBooksList(
          search: BookSearch(condition: nil),
          page: page,
          size: syncPageSize,
          sort: ["lastModified,desc"]
        )

        var itemsToSync: [Book] = []
        for book in result.content {
          if book.lastModified > since {
            itemsToSync.append(book)
          } else {
            shouldContinue = false
            break
          }
        }

        if !itemsToSync.isEmpty {
          await database.upsertBooks(itemsToSync, instanceId: instanceId)
        }

        page += 1
        if result.last {
          shouldContinue = false
        }

        await report(
          .books,
          progress: incrementalProgress(
            processedPages: page,
            totalPages: result.totalPages,
            finished: !shouldContinue
          ),
          stage: .booksIncremental,
          onProgress: onProgress
        )
      }
      logger.info("📖 Synced books incrementally")
      return true
    } catch {
      logger.error("❌ Failed to sync books: \(error)")
      await report(
        .books,
        progress: 1.0,
        stage: .booksIncremental,
        onProgress: onProgress
      )
      return false
    }
  }

  private func reconcileBookDeletions(
    instanceId: String,
    database: DatabaseOperator,
    onProgress: SyncProgressHandler
  ) async -> Bool {
    await report(
      .books,
      progress: 0.0,
      stage: .booksReconcile,
      onProgress: onProgress
    )
    do {
      let localCount = await database.fetchTotalBooksCount(instanceId: instanceId)
      do {
        let remoteCount = try await fetchRemoteBookCountForDeletionReconcile()
        if localCount <= remoteCount {
          logger.debug(
            "⏭️ Skipped book reconcile: localCount=\(localCount), remoteCount=\(remoteCount)"
          )
          await report(
            .books,
            progress: 1.0,
            stage: .booksReconcile,
            onProgress: onProgress
          )
          return true
        }
      } catch {
        logger.warning(
          "⚠️ Failed to preflight book reconcile counts, fallback to full scan: \(error)"
        )
      }

      let remoteBookIds = try await fetchAllBookIdsForDeletionReconcile(
        onProgress: onProgress
      )
      let deletedCount = await database.deleteBooksNotIn(
        remoteBookIds,
        instanceId: instanceId
      )
      if deletedCount > 0 {
        let cleanupResult = await OfflineManager.shared.cleanupOrphanedFiles()
        if cleanupResult.deletedCount > 0 {
          logger.info(
            "🧹 Cleaned \(cleanupResult.deletedCount) orphaned offline directories after stale book removal"
          )
        }
        logger.info("🧹 Removed \(deletedCount) stale books")
      }
      return true
    } catch {
      logger.error("❌ Failed to reconcile stale books: \(error)")
      return false
    }
  }

  private func fetchRemoteSeriesCountForDeletionReconcile() async throws -> Int {
    let result = try await SeriesService.getSeriesList(
      search: SeriesSearch(condition: nil),
      page: 0,
      size: 1,
      sort: "lastModified,desc"
    )
    return result.totalElements
  }

  private func fetchRemoteBookCountForDeletionReconcile() async throws -> Int {
    let result = try await BookService.getBooksList(
      search: BookSearch(condition: nil),
      page: 0,
      size: 1,
      sort: ["lastModified,desc"]
    )
    return result.totalElements
  }

  private func fetchAllSeriesIdsForDeletionReconcile(
    onProgress: SyncProgressHandler
  ) async throws -> Set<String> {
    do {
      let result = try await SeriesService.getSeriesList(
        search: SeriesSearch(condition: nil),
        sort: "lastModified,desc",
        unpaged: true
      )
      await report(
        .series,
        progress: 1.0,
        stage: .seriesReconcile,
        onProgress: onProgress
      )
      return Set(result.content.map(\.id))
    } catch {
      logger.warning("⚠️ Unpaged series reconcile failed, fallback to paged scan: \(error)")
    }

    var page = 0
    var hasMore = true
    var ids = Set<String>()
    while hasMore {
      let result = try await SeriesService.getSeriesList(
        search: SeriesSearch(condition: nil),
        page: page,
        size: syncPageSize,
        sort: "lastModified,desc"
      )
      ids.formUnion(result.content.map(\.id))
      hasMore = !result.last
      page += 1
      await report(
        .series,
        progress: min(Double(page) / Double(max(result.totalPages, 1)), 1.0),
        stage: .seriesReconcile,
        onProgress: onProgress
      )
    }
    return ids
  }

  private func fetchAllBookIdsForDeletionReconcile(
    onProgress: SyncProgressHandler
  ) async throws -> Set<String> {
    do {
      let result = try await BookService.getBooksList(
        search: BookSearch(condition: nil),
        sort: ["lastModified,desc"],
        unpaged: true
      )
      await report(
        .books,
        progress: 1.0,
        stage: .booksReconcile,
        onProgress: onProgress
      )
      return Set(result.content.map(\.id))
    } catch {
      logger.warning("⚠️ Unpaged book reconcile failed, fallback to paged scan: \(error)")
    }

    var page = 0
    var hasMore = true
    var ids = Set<String>()
    while hasMore {
      let result = try await BookService.getBooksList(
        search: BookSearch(condition: nil),
        page: page,
        size: syncPageSize,
        sort: ["lastModified,desc"]
      )
      ids.formUnion(result.content.map(\.id))
      hasMore = !result.last
      page += 1
      await report(
        .books,
        progress: min(Double(page) / Double(max(result.totalPages, 1)), 1.0),
        stage: .booksReconcile,
        onProgress: onProgress
      )
    }
    return ids
  }

  // Incremental scans stop when they reach the sync marker and the changed
  // count is unknowable upfront, so progress tracks the scanned fraction of
  // the whole library and jumps to 100% when the marker is hit early.
  private func incrementalProgress(
    processedPages: Int,
    totalPages: Int,
    finished: Bool
  ) -> Double {
    if finished { return 1.0 }
    return min(Double(processedPages) / Double(max(totalPages, 1)), 1.0)
  }

  private func report(
    _ phase: SyncPhase,
    progress: Double,
    stage: SyncStage? = nil,
    onProgress: SyncProgressHandler
  ) async {
    await onProgress(
      SyncProgress(
        phase: phase,
        phaseProgress: progress,
        stage: stage
      )
    )
  }
}
