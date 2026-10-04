//
// DatabaseOperator+Offline.swift
//
//

import Foundation
import GRDB

extension DatabaseOperator {
  func clearInstanceData(instanceId: String) {
    do {
      try write { db in
        try db.execute(sql: "DELETE FROM \(KomgaBook.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
        try db.execute(
          sql: "DELETE FROM \(KomgaSeries.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
        try db.execute(
          sql: "DELETE FROM \(KomgaCollection.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
        try db.execute(
          sql: "DELETE FROM \(ReadListBookMembership.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
        try db.execute(
          sql: "DELETE FROM \(ReadListReadingState.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
        try db.execute(
          sql: "DELETE FROM \(KomgaReadList.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
        try db.execute(
          sql: "DELETE FROM \(PendingProgress.databaseTableName) WHERE instance_id = ?", arguments: [instanceId])
      }
      logger.info("Cleared GRDB entities for instance: \(instanceId)")
    } catch {
      logger.error("Failed to clear instance data: \(error)")
    }
  }

  func fetchHistoricalEventLocalReferences(
    instanceId: String,
    bookIds: Set<String>,
    seriesIds: Set<String>
  ) throws -> HistoricalEventLocalReferences {
    guard !instanceId.isEmpty, !bookIds.isEmpty || !seriesIds.isEmpty else {
      return .empty
    }

    return try read { db in
      var bookNameById: [String: String] = [:]
      if !bookIds.isEmpty {
        let books = try fetchBooksByIds(db: db, ids: Array(bookIds), instanceId: instanceId)
        for book in books {
          bookNameById[book.bookId] = book.metaTitle
        }
      }

      var seriesNameById: [String: String] = [:]
      if !seriesIds.isEmpty {
        let series = try fetchSeriesByIds(db: db, ids: Array(seriesIds), instanceId: instanceId)
        for item in series {
          seriesNameById[item.seriesId] = item.metaTitle
        }
      }

      return HistoricalEventLocalReferences(
        bookNameById: bookNameById,
        seriesNameById: seriesNameById
      )
    }
  }

  func fetchOfflineTaskItems(instanceId: String) throws -> [OfflineTaskItem] {
    guard !instanceId.isEmpty else { return [] }
    return try read { db in
      let books = try KomgaBook.fetchAll(
        db,
        sql: """
          SELECT *
          FROM \(KomgaBook.databaseTableName)
          WHERE instance_id = ?
          AND download_status_raw IN ('pending', 'downloading', 'failed')
          ORDER BY download_at ASC, id ASC
          """,
        arguments: [instanceId]
      )
      return books.map { book in
        OfflineTaskItem(
          id: book.id,
          bookId: book.bookId,
          seriesTitle: book.seriesTitle,
          metaNumber: book.metaNumber,
          metaTitle: book.metaTitle,
          downloadStatusRaw: book.downloadStatusRaw,
          downloadStatus: book.downloadStatus,
          contentKind: book.downloadContentKind
        )
      }
    }
  }

  func fetchOfflineCoverSyncTargets(
    instanceId: String,
    libraryIds: [String] = []
  ) throws -> [OfflineCoverSyncTarget] {
    guard !instanceId.isEmpty else { return [] }
    return try read { db in
      var targets: [OfflineCoverSyncTarget] = []

      var seriesSQL = """
        SELECT series_id
        FROM \(KomgaSeries.databaseTableName)
        WHERE instance_id = ?
        AND is_unavailable = 0
        """
      var seriesArguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(
        column: "library_id",
        values: libraryIds,
        sql: &seriesSQL,
        arguments: &seriesArguments
      )
      seriesSQL += "\nORDER BY id ASC"
      let seriesIds = try String.fetchAll(
        db,
        sql: seriesSQL,
        arguments: seriesArguments
      )
      targets.append(
        contentsOf: seriesIds.map { OfflineCoverSyncTarget(thumbnailId: $0, type: .series) }
      )

      var bookSQL = """
        SELECT book_id
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
        AND is_unavailable = 0
        """
      var bookArguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(
        column: "library_id",
        values: libraryIds,
        sql: &bookSQL,
        arguments: &bookArguments
      )
      bookSQL += "\nORDER BY id ASC"
      let bookIds = try String.fetchAll(
        db,
        sql: bookSQL,
        arguments: bookArguments
      )
      targets.append(
        contentsOf: bookIds.map { OfflineCoverSyncTarget(thumbnailId: $0, type: .book) }
      )

      let readListIds = try String.fetchAll(
        db,
        sql: """
          SELECT read_list_id
          FROM \(KomgaReadList.databaseTableName)
          WHERE instance_id = ?
          ORDER BY id ASC
          """,
        arguments: [instanceId]
      )
      targets.append(
        contentsOf: readListIds.map { OfflineCoverSyncTarget(thumbnailId: $0, type: .readlist) }
      )

      let collectionIds = try String.fetchAll(
        db,
        sql: """
          SELECT collection_id
          FROM \(KomgaCollection.databaseTableName)
          WHERE instance_id = ?
          ORDER BY id ASC
          """,
        arguments: [instanceId]
      )
      targets.append(
        contentsOf: collectionIds.map {
          OfflineCoverSyncTarget(thumbnailId: $0, type: .collection)
        }
      )

      return targets
    }
  }

  func updateBookDownloadStatus(
    bookId: String,
    instanceId: String,
    status: DownloadStatus,
    downloadAt: Date? = nil,
    downloadedSize: Int64? = nil,
    syncSeriesStatus: Bool = true
  ) {
    do {
      try write { db in
        guard var book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else { return }
        let oldStatusRaw = book.downloadStatusRaw
        let oldDownloadedSize = book.downloadedSize
        let oldDownloadAt = book.downloadAt
        book.downloadStatus = status
        if let downloadAt {
          book.downloadAt = downloadAt
        }
        if let downloadedSize {
          book.downloadedSize = downloadedSize
        } else if case .notDownloaded = status {
          book.downloadedSize = 0
        }

        if case .notDownloaded = status {
          book.pagesRaw = nil
          book.tocRaw = nil
          book.webPubManifestRaw = nil
        }

        try save(book, db: db)

        guard syncSeriesStatus else { return }
        if var series = try fetchSeriesRecord(db: db, id: book.seriesId, instanceId: instanceId) {
          if series.offlinePolicy == .manual {
            applySeriesDownloadDelta(
              db: db,
              series: &series,
              oldStatusRaw: oldStatusRaw,
              newStatusRaw: book.downloadStatusRaw,
              oldDownloadedSize: oldDownloadedSize,
              newDownloadedSize: book.downloadedSize,
              oldDownloadAt: oldDownloadAt,
              newDownloadAt: book.downloadAt
            )
          } else {
            syncSeriesDownloadStatus(db: db, series: &series)
          }
          try save(series, db: db)
        }

        let readListIds = try fetchReadListIdsContainingBooks(db: db, instanceId: instanceId, bookIds: [book.bookId])
        var readLists = try fetchReadListsByIds(db: db, ids: readListIds, instanceId: instanceId)
        for index in readLists.indices {
          if readLists[index].offlinePolicy == .manual {
            applyReadListDownloadDelta(
              db: db,
              readList: &readLists[index],
              oldStatusRaw: oldStatusRaw,
              newStatusRaw: book.downloadStatusRaw,
              oldDownloadedSize: oldDownloadedSize,
              newDownloadedSize: book.downloadedSize,
              oldDownloadAt: oldDownloadAt,
              newDownloadAt: book.downloadAt
            )
          } else {
            syncReadListDownloadStatus(db: db, readList: &readLists[index])
          }
          try save(readLists[index], db: db)
        }
      }
    } catch {
      logger.error("Failed to update book download status: \(error)")
    }
  }

  func deleteLocalBookAfterNotFound(bookId: String, instanceId: String) {
    do {
      try write { db in
        guard let book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else { return }
        let seriesId = book.seriesId
        removeBookFromCachedReadLists(db: db, bookId: bookId, instanceId: instanceId)
        try KomgaBook.deleteOne(db, key: book.id)
        syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: instanceId)
      }
    } catch {
      logger.error("Failed to delete local book after not found: \(error)")
    }
  }

  func updateReadingProgress(bookId: String, page: Int, completed: Bool) {
    let instanceId = AppConfig.current.instanceId
    do {
      try write { db in
        guard var book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else { return }
        let oldStatus = readingStatus(
          progressCompleted: book.progressCompleted,
          progressPage: book.progressPage
        )
        let now = Date()
        let createdAt = book.readProgress?.created ?? now
        book.updateReadProgress(
          ReadProgress(
            page: page,
            completed: completed,
            readDate: now,
            created: createdAt,
            lastModified: now
          )
        )
        try save(book, db: db)

        let newStatus = readingStatus(
          progressCompleted: book.progressCompleted,
          progressPage: book.progressPage
        )
        if oldStatus != newStatus {
          updateSeriesReadingCounts(
            db: db,
            seriesId: book.seriesId,
            instanceId: instanceId,
            oldStatus: oldStatus,
            newStatus: newStatus
          )
        }
      }
    } catch {
      logger.error("Failed to update reading progress: \(error)")
    }
  }

  func updateEpubReadingProgressFromTotalProgression(
    bookId: String,
    totalProgression: Double?,
    fallbackPage: Int
  ) -> (page: Int, completed: Bool) {
    let instanceId = AppConfig.current.instanceId
    let normalized = min(max(totalProgression ?? 0, 0), 1)
    let completed = normalized >= 0.999_999
    var resolvedPage = max(0, fallbackPage)

    if let book = try? read({ db in try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) }) {
      let totalPages = max(0, book.mediaPagesCount)
      if totalPages > 0 {
        if completed {
          resolvedPage = totalPages - 1
        } else if normalized > 0 {
          let converted = Int((normalized * Double(totalPages)).rounded(.up)) - 1
          resolvedPage = min(max(0, converted), totalPages - 1)
        } else {
          resolvedPage = 0
        }
      }
    }

    updateReadingProgress(bookId: bookId, page: resolvedPage, completed: completed)
    return (resolvedPage, completed)
  }
}

extension DatabaseOperator {
  func syncSeriesDownloadStatus(series: KomgaSeries) {
    try? write { db in
      var series = series
      syncSeriesDownloadStatus(db: db, series: &series)
      try save(series, db: db)
    }
  }

  func syncSeriesDownloadStatus(seriesId: String, instanceId: String) {
    try? write { db in
      syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: instanceId)
    }
  }

  func downloadSeriesOffline(seriesId: String, instanceId: String) {
    updateSeriesBooksOffline(seriesId: seriesId, instanceId: instanceId, mode: .all)
  }

  func downloadSeriesUnreadOffline(seriesId: String, instanceId: String, limit: Int) {
    updateSeriesBooksOffline(seriesId: seriesId, instanceId: instanceId, mode: .unread(limit: limit))
  }

  func removeSeriesOffline(seriesId: String, instanceId: String, onlyBookIds: Set<String>? = nil) {
    removeSeriesBooksOffline(
      seriesId: seriesId, instanceId: instanceId, readOnly: false, onlyBookIds: onlyBookIds)
  }

  func removeSeriesReadOffline(
    seriesId: String, instanceId: String, onlyBookIds: Set<String>? = nil
  ) {
    removeSeriesBooksOffline(
      seriesId: seriesId, instanceId: instanceId, readOnly: true, onlyBookIds: onlyBookIds)
  }

  func toggleSeriesDownload(seriesId: String, instanceId: String) {
    guard let series = try? read({ db in try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) }) else {
      return
    }
    switch series.downloadStatus {
    case .downloaded, .partiallyDownloaded, .pending:
      removeSeriesOffline(seriesId: seriesId, instanceId: instanceId)
    case .notDownloaded, .failed:
      downloadSeriesOffline(seriesId: seriesId, instanceId: instanceId)
    }
  }

  func updateSeriesOfflinePolicy(
    seriesId: String,
    instanceId: String,
    policy: OfflinePolicy,
    limit: Int? = nil,
    syncSeriesStatus: Bool = true
  ) {
    do {
      try write { db in
        guard var series = try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else {
          return
        }
        series.offlinePolicy = policy
        if let limit {
          series.offlinePolicyLimit = max(0, limit)
        }
        if syncSeriesStatus {
          syncSeriesDownloadStatus(db: db, series: &series)
        }
        try save(series, db: db)
      }
    } catch {
      logger.error("Failed to update series offline policy: \(error)")
    }
  }

  func syncReadListDownloadStatus(readList: KomgaReadList) {
    try? write { db in
      var readList = readList
      syncReadListDownloadStatus(db: db, readList: &readList)
      try save(readList, db: db)
    }
  }

  func syncReadListDownloadStatus(readListId: String, instanceId: String) {
    try? write { db in
      guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
        return
      }
      syncReadListDownloadStatus(db: db, readList: &readList)
      try save(readList, db: db)
    }
  }

  func syncReadListsContainingBooks(bookIds: [String], instanceId: String) {
    guard !bookIds.isEmpty else { return }
    try? write { db in
      syncReadListsContainingBooksInTransaction(db: db, bookIds: bookIds, instanceId: instanceId)
    }
  }

  func downloadReadListOffline(readListId: String, instanceId: String) {
    updateReadListBooksOffline(readListId: readListId, instanceId: instanceId, mode: .all)
  }

  func downloadReadListUnreadOffline(readListId: String, instanceId: String, limit: Int) {
    updateReadListBooksOffline(readListId: readListId, instanceId: instanceId, mode: .unread(limit: limit))
  }

  func removeReadListOffline(readListId: String, instanceId: String, onlyBookIds: Set<String>? = nil) {
    removeReadListBooksOffline(
      readListId: readListId, instanceId: instanceId, readOnly: false, onlyBookIds: onlyBookIds)
  }

  func removeReadListReadOffline(
    readListId: String, instanceId: String, onlyBookIds: Set<String>? = nil
  ) {
    removeReadListBooksOffline(
      readListId: readListId, instanceId: instanceId, readOnly: true, onlyBookIds: onlyBookIds)
  }

  func updateReadListOfflinePolicy(
    readListId: String,
    instanceId: String,
    policy: OfflinePolicy,
    limit: Int? = nil,
    syncReadListStatus: Bool = true
  ) {
    do {
      try write { db in
        guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
          return
        }
        readList.offlinePolicy = policy
        if let limit {
          readList.offlinePolicyLimit = max(0, limit)
        }
        if syncReadListStatus {
          syncReadListDownloadStatus(db: db, readList: &readList)
        }
        try save(readList, db: db)
      }
    } catch {
      logger.error("Failed to update read-list offline policy: \(error)")
    }
  }

  func prepareReadListDownloadCancellation(readListId: String, instanceId: String) -> [String] {
    do {
      return try write { db in
        guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
          return []
        }
        readList.offlinePolicy = .manual
        let books = try fetchBooksByIds(db: db, ids: readList.bookIds, instanceId: instanceId)
        let cancellableBookIds =
          books
          .filter { ["pending", "downloading", "failed"].contains($0.downloadStatusRaw) }
          .map(\.bookId)
        try save(readList, db: db)
        return cancellableBookIds
      }
    } catch {
      logger.error("Failed to prepare read-list download cancellation: \(error)")
      return []
    }
  }

  func updateOfflineProtectionSourcesToManual(bookIds: [String], instanceId: String) {
    guard !bookIds.isEmpty else { return }
    do {
      try write { db in
        let targetBooks = try fetchBooksByIds(db: db, ids: bookIds, instanceId: instanceId)
        guard !targetBooks.isEmpty else { return }
        let books = try fetchBooks(db: db, instanceId: instanceId)
        let targetBookIds = targetBooks.map(\.bookId)
        let readListSources = try fetchReadListsAndMembershipsContainingBooks(
          db: db,
          instanceId: instanceId,
          bookIds: targetBookIds
        )

        let protectionIndex = OfflineProtectionIndex(
          books: books,
          series: try fetchSeriesByIds(
            db: db,
            ids: Array(Set(targetBooks.map(\.seriesId))),
            instanceId: instanceId
          ),
          readLists: readListSources.readLists,
          readListMemberships: readListSources.memberships
        )
        var protectedSeriesIds = Set<String>()
        var sourceReadListIds = Set<String>()

        for book in targetBooks {
          for source in protectionIndex.sources(for: book) {
            switch source.kind {
            case .series:
              protectedSeriesIds.insert(source.sourceId)
            case .readList:
              sourceReadListIds.insert(source.sourceId)
            }
          }
        }

        for seriesId in protectedSeriesIds {
          guard var series = try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else { continue }
          series.offlinePolicy = .manual
          try save(series, db: db)
        }

        var mutableReadLists = readListSources.readLists
        for index in mutableReadLists.indices {
          guard sourceReadListIds.contains(mutableReadLists[index].readListId) else { continue }
          mutableReadLists[index].offlinePolicy = .manual
          try save(mutableReadLists[index], db: db)
        }
      }
    } catch {
      logger.error("Failed to reset offline protection sources: \(error)")
    }
  }
}

extension DatabaseOperator {
  enum OfflineQueueMode {
    case all
    case unread(limit: Int)
  }

  func syncSeriesDownloadStatus(db: Database, seriesId: String, instanceId: String) {
    guard var series = try? fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else { return }
    syncSeriesDownloadStatus(db: db, series: &series)
    try? save(series, db: db)
  }

  func syncSeriesDownloadStatus(db: Database, series: inout KomgaSeries) {
    let books = (try? fetchBooks(db: db, instanceId: series.instanceId, seriesId: series.seriesId)) ?? []
    let totalCount = series.booksCount
    let downloadedCount = books.filter { $0.downloadStatusRaw == "downloaded" }.count
    let pendingCount = books.filter { $0.downloadStatusRaw == "pending" }.count
    let failedCount = books.filter { $0.downloadStatusRaw == "failed" }.count

    series.downloadedBooks = downloadedCount
    series.pendingBooks = pendingCount
    series.downloadedSize = books.reduce(0) { $0 + $1.downloadedSize }
    series.downloadAt = books.compactMap(\.downloadAt).max()

    if downloadedCount == totalCount {
      series.downloadStatusRaw = "downloaded"
    } else if pendingCount > 0 {
      series.downloadStatusRaw = "pending"
    } else if failedCount > 0 {
      series.downloadStatusRaw = "failed"
    } else {
      series.downloadStatusRaw = "notDownloaded"
    }

    handlePolicyActions(db: db, series: series, books: books)
  }

  func handlePolicyActions(db: Database, series: KomgaSeries, books: [KomgaBook]) {
    let policy = series.offlinePolicy
    guard policy != .manual else { return }

    var books = books
    var needsSyncQueue = false
    var queuedBookIds: [String] = []
    let policyLimit = max(0, series.offlinePolicyLimit)
    let sortedBooks =
      books
      .filter { !$0.isUnavailable }
      .sorted(by: KomgaBook.seriesOfflinePolicySort)
    var allowedUnreadIds = Set<String>()
    if policyLimit > 0, policy == .unreadOnly {
      let unreadBooks = sortedBooks.filter { $0.progressCompleted != true }
      allowedUnreadIds = Set(unreadBooks.prefix(policyLimit).map(\.bookId))
    }
    let now = Date.now

    for (sortedIndex, sourceBook) in sortedBooks.enumerated() {
      guard let index = books.firstIndex(where: { $0.id == sourceBook.id }) else { continue }
      let isRead = books[index].progressCompleted ?? false
      let isDownloaded = books[index].downloadStatusRaw == "downloaded"
      let isPending = books[index].downloadStatusRaw == "pending"
      let isFailed = books[index].downloadStatusRaw == "failed"

      var shouldBeOffline: Bool
      switch policy {
      case .manual:
        shouldBeOffline = (isDownloaded || isPending)
      case .unreadOnly:
        if isRead {
          shouldBeOffline = false
        } else if policyLimit > 0 {
          shouldBeOffline = allowedUnreadIds.contains(books[index].bookId)
        } else {
          shouldBeOffline = true
        }
      case .all:
        shouldBeOffline = true
      }

      if shouldBeOffline {
        if !isDownloaded && !isPending && !isFailed {
          books[index].downloadStatusRaw = "pending"
          books[index].downloadAt = now.addingTimeInterval(Double(sortedIndex) * 0.001)
          try? save(books[index], db: db)
          needsSyncQueue = true
          queuedBookIds.append(books[index].bookId)
        }
      }
    }
    syncReadListsContainingBooksInTransaction(db: db, bookIds: queuedBookIds, instanceId: series.instanceId)

    if needsSyncQueue {
      OfflineManager.shared.triggerSync(instanceId: series.instanceId)
    }
  }

  @discardableResult
  func handlePolicyActions(db: Database, readList: KomgaReadList, books: [KomgaBook]) -> Bool {
    let policy = readList.offlinePolicy
    guard policy != .manual else { return false }

    var books = books
    var needsSyncQueue = false
    var seriesIdsToSync = Set<String>()
    var queuedBookIds: [String] = []
    let policyLimit = max(0, readList.offlinePolicyLimit)
    let sortedBooks = books.filter { !$0.isUnavailable }
    var allowedUnreadIds = Set<String>()
    if policyLimit > 0, policy == .unreadOnly {
      let unreadBooks = sortedBooks.filter { $0.progressCompleted != true }
      allowedUnreadIds = Set(unreadBooks.prefix(policyLimit).map(\.bookId))
    }
    let now = Date.now

    for (sortedIndex, sourceBook) in sortedBooks.enumerated() {
      guard let index = books.firstIndex(where: { $0.id == sourceBook.id }) else { continue }
      let isRead = books[index].progressCompleted ?? false
      let isDownloaded = books[index].downloadStatusRaw == "downloaded"
      let isPending = books[index].downloadStatusRaw == "pending"
      let isFailed = books[index].downloadStatusRaw == "failed"

      var shouldBeOffline: Bool
      switch policy {
      case .manual:
        shouldBeOffline = isDownloaded || isPending
      case .unreadOnly:
        if isRead {
          shouldBeOffline = false
        } else if policyLimit > 0 {
          shouldBeOffline = allowedUnreadIds.contains(books[index].bookId)
        } else {
          shouldBeOffline = true
        }
      case .all:
        shouldBeOffline = true
      }

      if shouldBeOffline {
        if !isDownloaded && !isPending && !isFailed {
          books[index].downloadStatusRaw = "pending"
          books[index].downloadAt = now.addingTimeInterval(Double(sortedIndex) * 0.001)
          try? save(books[index], db: db)
          needsSyncQueue = true
          seriesIdsToSync.insert(books[index].seriesId)
          queuedBookIds.append(books[index].bookId)
        }
      }
    }

    for seriesId in seriesIdsToSync {
      syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: readList.instanceId)
    }
    syncReadListsContainingBooksInTransaction(
      db: db,
      bookIds: queuedBookIds,
      instanceId: readList.instanceId,
      excludingReadListId: readList.readListId
    )

    if needsSyncQueue {
      OfflineManager.shared.triggerSync(instanceId: readList.instanceId)
    }

    return needsSyncQueue
  }

  func applySeriesDownloadDelta(
    db: Database,
    series: inout KomgaSeries,
    oldStatusRaw: String,
    newStatusRaw: String,
    oldDownloadedSize: Int64,
    newDownloadedSize: Int64,
    oldDownloadAt: Date?,
    newDownloadAt: Date?
  ) {
    // The delta tracks only downloaded/pending counts; a failure anywhere
    // needs a full recount.
    if oldStatusRaw == "failed" || newStatusRaw == "failed"
      || series.downloadStatusRaw == "failed"
    {
      syncSeriesDownloadStatus(db: db, series: &series)
      return
    }

    let wasDownloaded = oldStatusRaw == "downloaded"
    let isDownloaded = newStatusRaw == "downloaded"
    let wasPending = oldStatusRaw == "pending"
    let isPending = newStatusRaw == "pending"

    var downloadedCount = series.downloadedBooks
    var pendingCount = series.pendingBooks
    var downloadedSize = series.downloadedSize

    if wasDownloaded && !isDownloaded {
      downloadedCount -= 1
      downloadedSize -= oldDownloadedSize
    } else if !wasDownloaded && isDownloaded {
      downloadedCount += 1
      downloadedSize += newDownloadedSize
    } else if wasDownloaded && isDownloaded && oldDownloadedSize != newDownloadedSize {
      downloadedSize += (newDownloadedSize - oldDownloadedSize)
    }

    if wasPending && !isPending {
      pendingCount -= 1
    } else if !wasPending && isPending {
      pendingCount += 1
    }

    if downloadedCount < 0 || pendingCount < 0
      || downloadedCount > series.booksCount
      || pendingCount > series.booksCount
    {
      syncSeriesDownloadStatus(db: db, series: &series)
      return
    }

    series.downloadedBooks = max(0, downloadedCount)
    series.pendingBooks = max(0, pendingCount)
    series.downloadedSize = max(0, downloadedSize)

    if let newDownloadAt, series.downloadAt == nil || newDownloadAt > series.downloadAt! {
      series.downloadAt = newDownloadAt
    } else if let oldDownloadAt, oldDownloadAt == series.downloadAt, newDownloadAt == nil {
      syncSeriesDownloadStatus(db: db, series: &series)
      return
    }

    if downloadedCount == series.booksCount {
      series.downloadStatusRaw = "downloaded"
    } else if pendingCount > 0 {
      series.downloadStatusRaw = "pending"
    } else {
      series.downloadStatusRaw = "notDownloaded"
    }
  }

  func syncReadListDownloadStatus(db: Database, readList: inout KomgaReadList) {
    let bookIds = readList.bookIds
    guard !bookIds.isEmpty else {
      readList.downloadedBooks = 0
      readList.pendingBooks = 0
      readList.downloadedSize = 0
      readList.downloadAt = nil
      readList.downloadStatusRaw = "notDownloaded"
      return
    }

    let books = (try? fetchBooksByIds(db: db, ids: bookIds, instanceId: readList.instanceId)) ?? []
    applyReadListDownloadSummary(readList: &readList, books: books, totalCount: bookIds.count)

    guard handlePolicyActions(db: db, readList: readList, books: books) else {
      return
    }

    let updatedBooks = (try? fetchBooksByIds(db: db, ids: bookIds, instanceId: readList.instanceId)) ?? []
    applyReadListDownloadSummary(readList: &readList, books: updatedBooks, totalCount: bookIds.count)
  }

  func applyReadListDownloadSummary(readList: inout KomgaReadList, books: [KomgaBook], totalCount: Int) {
    let downloadedBooks = books.filter { $0.downloadStatusRaw == "downloaded" }
    let pendingCount = books.filter { $0.downloadStatusRaw == "pending" || $0.downloadStatusRaw == "downloading" }.count
    let failedCount = books.filter { $0.downloadStatusRaw == "failed" }.count

    readList.downloadedBooks = downloadedBooks.count
    readList.pendingBooks = pendingCount
    readList.downloadedSize = downloadedBooks.reduce(0) { $0 + $1.downloadedSize }
    readList.downloadAt = downloadedBooks.compactMap(\.downloadAt).max()

    if readList.downloadedBooks == totalCount && totalCount > 0 {
      readList.downloadStatusRaw = "downloaded"
    } else if pendingCount > 0 {
      readList.downloadStatusRaw = "pending"
    } else if failedCount > 0 {
      readList.downloadStatusRaw = "failed"
    } else if readList.downloadedBooks > 0 {
      readList.downloadStatusRaw = "partiallyDownloaded"
    } else {
      readList.downloadStatusRaw = "notDownloaded"
    }
  }

  func applyReadListDownloadDelta(
    db: Database,
    readList: inout KomgaReadList,
    oldStatusRaw: String,
    newStatusRaw: String,
    oldDownloadedSize: Int64,
    newDownloadedSize: Int64,
    oldDownloadAt: Date?,
    newDownloadAt: Date?
  ) {
    // The delta tracks only downloaded/pending counts; a failure anywhere
    // needs a full recount.
    if oldStatusRaw == "failed" || newStatusRaw == "failed"
      || readList.downloadStatusRaw == "failed"
    {
      syncReadListDownloadStatus(db: db, readList: &readList)
      return
    }

    let wasDownloaded = oldStatusRaw == "downloaded"
    let isDownloaded = newStatusRaw == "downloaded"
    let wasPending = oldStatusRaw == "pending"
    let isPending = newStatusRaw == "pending"

    var downloadedCount = readList.downloadedBooks
    var pendingCount = readList.pendingBooks
    var downloadedSize = readList.downloadedSize

    if wasDownloaded && !isDownloaded {
      downloadedCount -= 1
      downloadedSize -= oldDownloadedSize
    } else if !wasDownloaded && isDownloaded {
      downloadedCount += 1
      downloadedSize += newDownloadedSize
    } else if wasDownloaded && isDownloaded && oldDownloadedSize != newDownloadedSize {
      downloadedSize += (newDownloadedSize - oldDownloadedSize)
    }

    if wasPending && !isPending {
      pendingCount -= 1
    } else if !wasPending && isPending {
      pendingCount += 1
    }

    if downloadedCount < 0 || pendingCount < 0
      || downloadedCount > readList.bookIds.count
      || pendingCount > readList.bookIds.count
    {
      syncReadListDownloadStatus(db: db, readList: &readList)
      return
    }

    readList.downloadedBooks = max(0, downloadedCount)
    readList.pendingBooks = max(0, pendingCount)
    readList.downloadedSize = max(0, downloadedSize)

    if isDownloaded, let newDownloadAt {
      if readList.downloadAt == nil || newDownloadAt > readList.downloadAt! {
        readList.downloadAt = newDownloadAt
      }
    } else if downloadedCount == 0 {
      readList.downloadAt = nil
    } else if let oldDownloadAt, oldDownloadAt == readList.downloadAt {
      syncReadListDownloadStatus(db: db, readList: &readList)
      return
    }

    let totalCount = readList.bookIds.count
    if downloadedCount == totalCount && totalCount > 0 {
      readList.downloadStatusRaw = "downloaded"
    } else if pendingCount > 0 {
      readList.downloadStatusRaw = "pending"
    } else if downloadedCount > 0 {
      readList.downloadStatusRaw = "partiallyDownloaded"
    } else {
      readList.downloadStatusRaw = "notDownloaded"
    }
  }

  func removeBookFromCachedReadLists(db: Database, bookId: String, instanceId: String) {
    guard var readLists = try? fetchReadLists(db: db, instanceId: instanceId) else { return }
    for index in readLists.indices where readLists[index].bookIds.contains(bookId) {
      readLists[index].bookIds = readLists[index].bookIds.filter { $0 != bookId }
      try? replaceReadListBookMemberships(db: db, readList: readLists[index])
      syncReadListDownloadStatus(db: db, readList: &readLists[index])
      try? save(readLists[index], db: db)
    }
  }

  func shouldKeepBookDueToOtherPolicies(
    book: KomgaBook,
    protectionIndex: OfflineProtectionIndex,
    excludeSeriesId: String? = nil,
    excludeReadListId: String? = nil
  ) -> Bool {
    protectionIndex.sources(for: book).contains { source in
      switch source.kind {
      case .series:
        return source.sourceId != excludeSeriesId
      case .readList:
        return source.sourceId != excludeReadListId
      }
    }
  }

  func updateSeriesBooksOffline(seriesId: String, instanceId: String, mode: OfflineQueueMode) {
    do {
      var shouldTriggerSync = false
      try write { db in
        guard var series = try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else {
          return
        }
        series.offlinePolicy = .manual
        var affectedBookIds: [String] = []
        var books = try fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)
          .sorted(by: KomgaBook.seriesOfflinePolicySort)
        if case .unread(let limit) = mode {
          let unreadBooks = books.filter { $0.progressCompleted != true }
          let limitValue = max(0, limit)
          let targetIds = Set((limitValue > 0 ? Array(unreadBooks.prefix(limitValue)) : unreadBooks).map(\.bookId))
          books = books.filter { targetIds.contains($0.bookId) }
        }

        let now = Date.now
        for index in books.indices {
          if AppConfig.offlineAutoDeleteRead && books[index].progressCompleted == true {
            continue
          }
          if books[index].downloadStatusRaw != "downloaded" && books[index].downloadStatusRaw != "pending" {
            books[index].downloadStatusRaw = "pending"
            books[index].downloadAt = now.addingTimeInterval(Double(index) * 0.001)
            try save(books[index], db: db)
            shouldTriggerSync = true
            affectedBookIds.append(books[index].bookId)
          }
        }
        syncSeriesDownloadStatus(db: db, series: &series)
        syncReadListsContainingBooksInTransaction(db: db, bookIds: affectedBookIds, instanceId: instanceId)
        try save(series, db: db)
      }
      if shouldTriggerSync {
        OfflineManager.shared.triggerSync(instanceId: instanceId)
      }
    } catch {
      logger.error("Failed to update series offline queue: \(error)")
    }
  }

  /// Ids of a series' downloaded books, mirroring the removal candidate set
  /// (minus other-policy protection); `readOnly` keeps only completed ones.
  func fetchSeriesDownloadedBookIds(seriesId: String, instanceId: String, readOnly: Bool) -> [String] {
    (try? read { db in
      var books = try fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)
        .filter { $0.downloadStatusRaw == "downloaded" }
      if readOnly {
        books = books.filter { $0.progressCompleted == true }
      }
      return books.map(\.bookId)
    }) ?? []
  }

  /// Ids of a read list's downloaded books, mirroring the removal candidate set
  /// (minus other-policy protection); `readOnly` keeps only completed ones.
  func fetchReadListDownloadedBookIds(readListId: String, instanceId: String, readOnly: Bool) -> [String] {
    (try? read { db in
      guard let readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
        return []
      }
      var books = try fetchBooksByIds(db: db, ids: readList.bookIds, instanceId: instanceId)
        .filter { $0.downloadStatusRaw == "downloaded" }
      if readOnly {
        books = books.filter { $0.progressCompleted == true }
      }
      return books.map(\.bookId)
    }) ?? []
  }

  /// `onlyBookIds` bounds the removal to a staged set (undoable deletions): books
  /// downloaded after staging are left alone.
  func removeSeriesBooksOffline(
    seriesId: String, instanceId: String, readOnly: Bool, onlyBookIds: Set<String>? = nil
  ) {
    do {
      var bookIdsToRemove: [String] = []
      var affectedBookIds: [String] = []
      try write { db in
        guard var series = try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else {
          return
        }
        series.offlinePolicy = .manual
        var books = try fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)
        let readListSources = try fetchReadListsAndMembershipsContainingBooks(
          db: db,
          instanceId: instanceId,
          bookIds: books.map(\.bookId)
        )
        let protectionIndex = OfflineProtectionIndex(
          books: try fetchBooks(db: db, instanceId: instanceId),
          series: [series],
          readLists: readListSources.readLists,
          readListMemberships: readListSources.memberships
        )
        for index in books.indices {
          if readOnly && books[index].progressCompleted != true {
            continue
          }
          if let onlyBookIds, !onlyBookIds.contains(books[index].bookId) {
            continue
          }
          if shouldKeepBookDueToOtherPolicies(
            book: books[index],
            protectionIndex: protectionIndex,
            excludeSeriesId: series.seriesId
          ) {
            continue
          }
          books[index].downloadStatusRaw = "notDownloaded"
          books[index].downloadError = nil
          books[index].downloadAt = nil
          books[index].downloadedSize = 0
          books[index].pagesRaw = nil
          books[index].tocRaw = nil
          books[index].webPubManifestRaw = nil
          try save(books[index], db: db)
          bookIdsToRemove.append(books[index].bookId)
          affectedBookIds.append(books[index].bookId)
        }
        syncSeriesDownloadStatus(db: db, series: &series)
        syncReadListsContainingBooksInTransaction(db: db, bookIds: affectedBookIds, instanceId: instanceId)
        try save(series, db: db)
      }
      Task {
        if !affectedBookIds.isEmpty {
          await ContentProjectionNotifier.postBooksAndSeriesDidChange(
            bookIds: affectedBookIds,
            instanceId: instanceId,
            reason: .downloadStatus
          )
        }
        for bookId in bookIdsToRemove {
          await OfflineManager.shared.deleteBook(
            instanceId: instanceId, bookId: bookId, commit: false, syncSeriesStatus: false)
        }
        self.syncSeriesDownloadStatus(seriesId: seriesId, instanceId: instanceId)
      }
    } catch {
      logger.error("Failed to remove series offline books: \(error)")
    }
  }

  func updateReadListBooksOffline(readListId: String, instanceId: String, mode: OfflineQueueMode) {
    do {
      var shouldTriggerSync = false
      try write { db in
        guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
          return
        }
        var seriesIdsToSync = Set<String>()
        var affectedBookIds: [String] = []
        readList.offlinePolicy = .manual
        var books = try fetchBooksByIds(db: db, ids: readList.bookIds, instanceId: instanceId)
        if case .unread(let limit) = mode {
          let unreadBooks = books.filter { $0.progressCompleted != true }
          let limitValue = max(0, limit)
          let targetIds = Set((limitValue > 0 ? Array(unreadBooks.prefix(limitValue)) : unreadBooks).map(\.bookId))
          books = books.filter { targetIds.contains($0.bookId) }
        }
        let now = Date.now
        for index in books.indices {
          if AppConfig.offlineAutoDeleteRead && books[index].progressCompleted == true {
            continue
          }
          if books[index].downloadStatusRaw != "downloaded" && books[index].downloadStatusRaw != "pending" {
            books[index].downloadStatusRaw = "pending"
            books[index].downloadAt = now.addingTimeInterval(Double(index) * 0.001)
            try save(books[index], db: db)
            shouldTriggerSync = true
            seriesIdsToSync.insert(books[index].seriesId)
            affectedBookIds.append(books[index].bookId)
          }
        }
        for seriesId in seriesIdsToSync {
          syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: instanceId)
        }
        syncReadListsContainingBooksInTransaction(
          db: db,
          bookIds: affectedBookIds,
          instanceId: instanceId,
          excludingReadListId: readList.readListId
        )
        syncReadListDownloadStatus(db: db, readList: &readList)
        try save(readList, db: db)
      }
      if shouldTriggerSync {
        OfflineManager.shared.triggerSync(instanceId: instanceId)
      }
    } catch {
      logger.error("Failed to update read-list offline queue: \(error)")
    }
  }

  /// `onlyBookIds` bounds the removal to a staged set (undoable deletions): books
  /// downloaded after staging are left alone.
  func removeReadListBooksOffline(
    readListId: String, instanceId: String, readOnly: Bool, onlyBookIds: Set<String>? = nil
  ) {
    do {
      var bookIdsToRemove: [String] = []
      var affectedBookIds: [String] = []
      try write { db in
        guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
          return
        }
        var seriesIdsToSync = Set<String>()
        readList.offlinePolicy = .manual
        var books = try fetchBooksByIds(db: db, ids: readList.bookIds, instanceId: instanceId)
        let readListSources = try fetchReadListsAndMembershipsContainingBooks(
          db: db,
          instanceId: instanceId,
          bookIds: books.map(\.bookId)
        )
        let protectionIndex = OfflineProtectionIndex(
          books: try fetchBooks(db: db, instanceId: instanceId),
          series: try fetchSeriesByIds(
            db: db,
            ids: Array(Set(books.map(\.seriesId))),
            instanceId: instanceId
          ),
          readLists: readListSources.readLists,
          readListMemberships: readListSources.memberships
        )
        for index in books.indices {
          if readOnly && books[index].progressCompleted != true {
            continue
          }
          if let onlyBookIds, !onlyBookIds.contains(books[index].bookId) {
            continue
          }
          if shouldKeepBookDueToOtherPolicies(
            book: books[index],
            protectionIndex: protectionIndex,
            excludeReadListId: readList.readListId
          ) {
            continue
          }
          books[index].downloadStatusRaw = "notDownloaded"
          books[index].downloadError = nil
          books[index].downloadAt = nil
          books[index].downloadedSize = 0
          books[index].pagesRaw = nil
          books[index].tocRaw = nil
          books[index].webPubManifestRaw = nil
          try save(books[index], db: db)
          bookIdsToRemove.append(books[index].bookId)
          seriesIdsToSync.insert(books[index].seriesId)
          affectedBookIds.append(books[index].bookId)
        }
        for seriesId in seriesIdsToSync {
          syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: instanceId)
        }
        syncReadListsContainingBooksInTransaction(
          db: db,
          bookIds: affectedBookIds,
          instanceId: instanceId,
          excludingReadListId: readList.readListId
        )
        syncReadListDownloadStatus(db: db, readList: &readList)
        try save(readList, db: db)
      }
      Task {
        if !affectedBookIds.isEmpty {
          await ContentProjectionNotifier.postBooksAndSeriesDidChange(
            bookIds: affectedBookIds,
            instanceId: instanceId,
            reason: .downloadStatus
          )
          await ContentProjectionNotifier.postReadListDidChange(readListId: readListId)
        }
        for bookId in bookIdsToRemove {
          await OfflineManager.shared.deleteBook(
            instanceId: instanceId, bookId: bookId, commit: false, syncSeriesStatus: false)
        }
        self.syncReadListDownloadStatus(readListId: readListId, instanceId: instanceId)
      }
    } catch {
      logger.error("Failed to remove read-list offline books: \(error)")
    }
  }
}
