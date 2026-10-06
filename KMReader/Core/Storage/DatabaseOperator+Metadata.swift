//
// DatabaseOperator+Metadata.swift
//
//

import Foundation
import GRDB

extension DatabaseOperator {
  func fetchSidebarLibraries(instanceId: String) throws -> [SidebarLibraryItem] {
    guard !instanceId.isEmpty else { return [] }
    return try read { db in
      try fetchLibraryRecords(db: db, instanceId: instanceId)
        .filter { $0.libraryId != KomgaLibrary.allLibrariesId }
        .sorted { $0.name < $1.name }
        .map(Self.makeSidebarLibraryItem)
    }
  }

  func fetchAllLibrariesItem(instanceId: String) throws -> SidebarLibraryItem? {
    guard !instanceId.isEmpty else { return nil }
    return try read { db in
      try fetchLibraryRecords(db: db, instanceId: instanceId)
        .first { $0.libraryId == KomgaLibrary.allLibrariesId }
        .map(Self.makeSidebarLibraryItem)
    }
  }

  func updateLibraryMetrics(
    instanceId: String,
    metricsByLibrary: [String: LibraryMetricValues]
  ) throws {
    guard !instanceId.isEmpty, !metricsByLibrary.isEmpty else { return }
    try write { db in
      var libraries = try fetchLibraryRecords(db: db, instanceId: instanceId)
      for index in libraries.indices {
        guard let metrics = metricsByLibrary[libraries[index].libraryId] else { continue }
        libraries[index].fileSize = metrics.fileSize
        libraries[index].booksCount = metrics.booksCount
        libraries[index].seriesCount = metrics.seriesCount
        libraries[index].sidecarsCount = metrics.sidecarsCount
        libraries[index].collectionsCount = metrics.collectionsCount
        libraries[index].readlistsCount = metrics.readlistsCount
        try save(libraries[index], db: db)
      }
    }
  }

  /// Drops every stored library metric of the instance: servers without the
  /// stats endpoints show no metrics, so previously stored numbers must not linger.
  func clearLibraryMetrics(instanceId: String) throws {
    guard !instanceId.isEmpty else { return }
    try write { db in
      var libraries = try fetchLibraryRecords(db: db, instanceId: instanceId)
      for index in libraries.indices {
        libraries[index].fileSize = nil
        libraries[index].booksCount = nil
        libraries[index].seriesCount = nil
        libraries[index].sidecarsCount = nil
        libraries[index].collectionsCount = nil
        libraries[index].readlistsCount = nil
        try save(libraries[index], db: db)
      }
    }
  }

  func replaceLibraries(_ libraries: [LibraryInfo], for instanceId: String) throws {
    try write { db in
      let existing = try fetchLibraryRecords(db: db, instanceId: instanceId)
      var existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.libraryId, $0) })

      for library in libraries {
        if var existingLibrary = existingMap[library.id] {
          existingLibrary.name = library.name
          try save(existingLibrary, db: db)
          existingMap.removeValue(forKey: library.id)
        } else {
          try save(
            KomgaLibrary(
              instanceId: instanceId,
              libraryId: library.id,
              name: library.name
            ),
            db: db
          )
        }
      }

      for (_, library) in existingMap where library.libraryId != KomgaLibrary.allLibrariesId {
        try KomgaLibrary.deleteOne(db, key: library.id)
      }
    }
  }

  func deleteLibrary(libraryId: String, instanceId: String) {
    try? write { db in
      try db.execute(
        sql: "DELETE FROM \(KomgaLibrary.databaseTableName) WHERE instance_id = ? AND library_id = ?",
        arguments: [instanceId, libraryId]
      )
      try db.execute(
        sql: "DELETE FROM \(KomgaBook.databaseTableName) WHERE instance_id = ? AND library_id = ?",
        arguments: [instanceId, libraryId]
      )
      try db.execute(
        sql: "DELETE FROM \(KomgaSeries.databaseTableName) WHERE instance_id = ? AND library_id = ?",
        arguments: [instanceId, libraryId]
      )
    }
  }

  func deleteLibraries(instanceId: String?) throws {
    try write { db in
      if let instanceId {
        for library in try fetchLibraryRecords(db: db, instanceId: instanceId) {
          try KomgaLibrary.deleteOne(db, key: library.id)
        }
      } else {
        try db.execute(sql: "DELETE FROM \(KomgaLibrary.databaseTableName)")
      }
    }
  }

  func upsertAllLibrariesEntry(
    instanceId: String,
    fileSize: Double?,
    booksCount: Double?,
    seriesCount: Double?,
    sidecarsCount: Double?,
    collectionsCount: Double?,
    readlistsCount: Double?
  ) throws {
    try write { db in
      let allLibrariesId = KomgaLibrary.allLibrariesId
      var library =
        try fetchLibraryRecords(db: db, instanceId: instanceId)
        .first { $0.libraryId == allLibrariesId }
        ?? KomgaLibrary(
          instanceId: instanceId,
          libraryId: allLibrariesId,
          name: "All Libraries"
        )
      library.fileSize = fileSize
      library.booksCount = booksCount
      library.seriesCount = seriesCount
      library.sidecarsCount = sidecarsCount
      library.collectionsCount = collectionsCount
      library.readlistsCount = readlistsCount
      try save(library, db: db)
    }
  }

  func retryFailedBooks(instanceId: String) {
    try? write { db in
      var books =
        try KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw == "failed")
        .fetchAll(db)
      for index in books.indices {
        books[index].downloadStatusRaw = "pending"
        books[index].downloadError = nil
        books[index].downloadAt = Date.now
        try save(books[index], db: db)
      }
      recountDownloadAggregates(db: db, books: books, instanceId: instanceId)
    }
  }

  func cancelFailedBooks(instanceId: String) {
    try? write { db in
      var books =
        try KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw == "failed")
        .fetchAll(db)
      for index in books.indices {
        books[index].downloadStatusRaw = "notDownloaded"
        books[index].downloadError = nil
        books[index].downloadAt = nil
        try save(books[index], db: db)
      }
      recountDownloadAggregates(db: db, books: books, instanceId: instanceId)
    }
  }

  /// Bulk status writes bypass the per-book delta path, so the series/read-list
  /// rollups are recounted explicitly.
  private func recountDownloadAggregates(db: Database, books: [KomgaBook], instanceId: String) {
    for seriesId in Set(books.map(\.seriesId)) {
      syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: instanceId)
    }
    syncReadListsContainingBooksInTransaction(db: db, bookIds: books.map(\.bookId), instanceId: instanceId)
  }
}

extension DatabaseOperator {
  func fetchSavedFilterDisplayItems(filterType: SavedFilterType) throws -> [SavedFilterDisplayItem] {
    try read { db in
      try SavedFilter.fetchAll(db)
        .filter { $0.filterType == filterType }
        .sorted { $0.updatedAt > $1.updatedAt }
        .map { filter in
          SavedFilterDisplayItem(
            id: filter.id,
            name: filter.name,
            filterType: filter.filterType,
            filterDataJSON: filter.filterDataJSON,
            updatedAt: filter.updatedAt
          )
        }
    }
  }

  func createSavedFilter(
    name: String,
    filterType: SavedFilterType,
    filterDataJSON: String
  ) throws {
    try write { db in
      try save(SavedFilter(name: name, filterType: filterType, filterDataJSON: filterDataJSON), db: db)
    }
  }

  func renameSavedFilter(id: UUID, name: String) throws {
    try write { db in
      guard var filter = try SavedFilter.fetchOne(db, key: id) else { return }
      filter.name = name
      filter.updatedAt = Date()
      try save(filter, db: db)
    }
  }

  func deleteSavedFilter(id: UUID) throws {
    _ = try write { db in
      try SavedFilter.deleteOne(db, key: id)
    }
  }

  func fetchEpubThemePresetDisplayItems() throws -> [EpubThemePresetDisplayItem] {
    try read { db in
      try EpubThemePreset.fetchAll(db)
        .sorted { $0.updatedAt > $1.updatedAt }
        .map { preset in
          EpubThemePresetDisplayItem(
            id: preset.id,
            name: preset.name,
            preferencesJSON: preset.preferencesJSON,
            updatedAt: preset.updatedAt
          )
        }
    }
  }

  func createEpubThemePreset(name: String, preferencesJSON: String) throws {
    try write { db in
      try save(EpubThemePreset(name: name, preferencesJSON: preferencesJSON), db: db)
    }
  }

  func renameEpubThemePreset(id: UUID, name: String) throws {
    try write { db in
      guard var preset = try EpubThemePreset.fetchOne(db, key: id) else { return }
      preset.name = name
      preset.updatedAt = Date()
      try save(preset, db: db)
    }
  }

  func deleteEpubThemePreset(id: UUID) throws {
    _ = try write { db in
      try EpubThemePreset.deleteOne(db, key: id)
    }
  }

  func fetchCustomFontDisplayItems() throws -> [CustomFontDisplayItem] {
    try read { db in
      try CustomFont.fetchAll(db)
        .sorted { $0.name < $1.name }
        .map(Self.makeCustomFontDisplayItem)
    }
  }

  func fetchCustomFontPath(name: String) throws -> String? {
    try read { db in
      try CustomFont.fetchOne(db, key: name)?.path
    }
  }

  func customFontExists(name: String) throws -> Bool {
    try read { db in
      try CustomFont.fetchOne(db, key: name) != nil
    }
  }

  func createCustomFont(
    name: String,
    path: String? = nil,
    fileName: String? = nil,
    fileSize: Int64? = nil
  ) throws {
    try write { db in
      try save(CustomFont(name: name, path: path, fileName: fileName, fileSize: fileSize), db: db)
    }
  }

  func deleteCustomFont(name: String) throws {
    _ = try write { db in
      try CustomFont.deleteOne(db, key: name)
    }
  }
}

extension DatabaseOperator {
  func upsertInstance(
    serverURL: String,
    username: String,
    authToken: String,
    isAdmin: Bool,
    authMethod: AuthenticationMethod = .basicAuth,
    apiKeyId: String? = nil,
    displayName: String? = nil,
    instanceId: UUID? = nil
  ) throws -> InstanceSummary {
    // Self-sufficient normalization (callers normalize too, but this must
    // hold regardless of caller): both the stored row's URL and the incoming
    // URL are compared in normalized form, so a legacy row persisted with a
    // trailing slash still matches a re-login for the same account instead
    // of spawning a duplicate instance — which would orphan everything keyed
    // to the old instance ID (protected flag, library selection, offline
    // downloads, last-used state).
    let serverURL = Current.normalizeServerURL(serverURL)
    return try write { db in
      let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let instances = try KomgaInstance.fetchAll(db)
      if var existing = instances.first(where: {
        Current.normalizeServerURL($0.serverURL) == serverURL && $0.username == username
      }) {
        // Heal legacy rows on touch: rewrite the stored URL in normalized
        // form so the row converges to the invariant without a migration.
        existing.serverURL = serverURL
        existing.authToken = authToken
        existing.isAdmin = isAdmin
        existing.authMethod = authMethod
        existing.apiKeyId = apiKeyId
        existing.lastUsedAt = Date()
        if let trimmedDisplayName, !trimmedDisplayName.isEmpty {
          existing.name = trimmedDisplayName
        } else if existing.name.isEmpty {
          existing.name = Self.defaultName(serverURL: serverURL, username: username)
        }
        try save(existing, db: db)
        return InstanceSummary(
          id: existing.id,
          displayName: existing.displayName,
          protected: existing.protected
        )
      }

      let resolvedName = Self.resolvedName(
        displayName: trimmedDisplayName,
        serverURL: serverURL,
        username: username
      )
      let instance = KomgaInstance(
        id: instanceId ?? UUID(),
        name: resolvedName,
        serverURL: serverURL,
        username: username,
        authToken: authToken,
        isAdmin: isAdmin,
        authMethod: authMethod,
        apiKeyId: apiKeyId
      )
      try save(instance, db: db)
      return InstanceSummary(
        id: instance.id,
        displayName: instance.displayName,
        protected: instance.protected
      )
    }
  }

  func updateInstanceLastUsed(instanceId: String) {
    guard let uuid = UUID(uuidString: instanceId) else { return }
    try? write { db in
      guard var instance = try KomgaInstance.fetchOne(db, key: uuid) else { return }
      instance.lastUsedAt = Date()
      try save(instance, db: db)
    }
  }

  func fetchInstanceApiKeyId(instanceId: String) throws -> String? {
    guard let uuid = UUID(uuidString: instanceId) else { return nil }
    return try read { db in
      try KomgaInstance.fetchOne(db, key: uuid)?.apiKeyId
    }
  }

  func updateInstanceApiKeyId(_ apiKeyId: String?, instanceId: String) throws {
    guard let uuid = UUID(uuidString: instanceId) else { return }
    try write { db in
      guard var instance = try KomgaInstance.fetchOne(db, key: uuid) else { return }
      instance.apiKeyId = apiKeyId
      try save(instance, db: db)
    }
  }

  func fetchServerDisplayItems(includeProtected: Bool = false) throws -> [ServerDisplayItem] {
    try read { db in
      try KomgaInstance.fetchAll(db)
        .filter { includeProtected || !$0.protected }
        .sorted {
          if $0.lastUsedAt != $1.lastUsedAt {
            return $0.lastUsedAt > $1.lastUsedAt
          }
          return $0.name < $1.name
        }
        .map(Self.makeServerDisplayItem)
    }
  }

  func fetchProtectedServerCount() throws -> Int {
    try read { db in
      try KomgaInstance
        .filter(Column("protected") == true)
        .fetchCount(db)
    }
  }

  func isServerProtected(instanceId: String) throws -> Bool {
    guard let uuid = UUID(uuidString: instanceId) else { return false }
    return try read { db in
      try KomgaInstance.fetchOne(db, key: uuid)?.protected ?? false
    }
  }

  func fetchSelectedLibraryIds(instanceId: String) throws -> [String]? {
    guard let uuid = UUID(uuidString: instanceId) else { return nil }
    return try read { db in
      guard let instance = try KomgaInstance.fetchOne(db, key: uuid) else { return nil }
      guard instance.selectedLibraryIdsRaw != nil else { return nil }
      return instance.selectedLibraryIds
    }
  }

  func updateSelectedLibraryIds(_ libraryIds: [String], instanceId: String) throws {
    guard let uuid = UUID(uuidString: instanceId) else { return }
    try write { db in
      guard var instance = try KomgaInstance.fetchOne(db, key: uuid) else { return }
      instance.selectedLibraryIds = libraryIds
      try save(instance, db: db)
    }
  }

  func updateServerDisplayItem(
    id: UUID,
    name: String,
    serverURL: String,
    username: String,
    authToken: String,
    authMethod: AuthenticationMethod,
    apiKeyId: String? = nil,
    protected: Bool
  ) throws -> ServerDisplayItem? {
    try write { db in
      guard var instance = try KomgaInstance.fetchOne(db, key: id) else { return nil }
      instance.name = name
      instance.serverURL = serverURL
      instance.username = username
      // A replaced credential drops the recorded auto-created key association
      // unless the caller just created that key and passes its id; without an
      // id the deterministic key comment re-heals the association on the next
      // API keys view if the same key is still in use.
      if instance.authToken != authToken {
        instance.apiKeyId = apiKeyId
      }
      instance.authToken = authToken
      instance.authMethod = authMethod
      instance.protected = protected
      instance.lastUsedAt = Date()
      try save(instance, db: db)
      return Self.makeServerDisplayItem(instance)
    }
  }

  func deleteServerDisplayItem(id: UUID) throws {
    _ = try write { db in
      try KomgaInstance.deleteOne(db, key: id)
    }
  }

  func updateSeriesLastSyncedAt(instanceId: String, date: Date) throws {
    guard let uuid = UUID(uuidString: instanceId) else { return }
    try write { db in
      guard var instance = try KomgaInstance.fetchOne(db, key: uuid) else { return }
      instance.seriesLastSyncedAt = date
      try save(instance, db: db)
    }
  }

  func updateBooksLastSyncedAt(instanceId: String, date: Date) throws {
    guard let uuid = UUID(uuidString: instanceId) else { return }
    try write { db in
      guard var instance = try KomgaInstance.fetchOne(db, key: uuid) else { return }
      instance.booksLastSyncedAt = date
      try save(instance, db: db)
    }
  }

  func fetchInstance(idString: String?) -> KomgaInstance? {
    guard let idString, let uuid = UUID(uuidString: idString) else { return nil }
    return try? read { db in
      try KomgaInstance.fetchOne(db, key: uuid)
    }
  }

  func getLastSyncedAt(instanceId: String) -> (series: Date, books: Date) {
    guard let instance = fetchInstance(idString: instanceId) else {
      return (Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 0))
    }
    return (instance.seriesLastSyncedAt, instance.booksLastSyncedAt)
  }

  func fetchOfflineInstanceSyncInfo(instanceId: String) throws -> OfflineInstanceSyncInfo? {
    guard let uuid = UUID(uuidString: instanceId) else { return nil }
    return try read { db in
      guard let instance = try KomgaInstance.fetchOne(db, key: uuid) else { return nil }
      return OfflineInstanceSyncInfo(
        instanceId: instanceId,
        seriesLastSyncedAt: instance.seriesLastSyncedAt,
        booksLastSyncedAt: instance.booksLastSyncedAt
      )
    }
  }

  func fetchLibraries(instanceId: String) -> [LibraryInfo] {
    (try? read { db in
      try fetchLibraryRecords(db: db, instanceId: instanceId)
        .sorted { $0.name < $1.name }
        .map { LibraryInfo(id: $0.libraryId, name: $0.name) }
    }) ?? []
  }
}

extension DatabaseOperator {
  func getDownloadStatus(bookId: String) -> DownloadStatus {
    getDownloadStatus(bookId: bookId, instanceId: AppConfig.current.instanceId)
  }

  func getDownloadStatus(bookId: String, instanceId: String) -> DownloadStatus {
    guard !instanceId.isEmpty else { return .notDownloaded }
    return
      (try? read { db in
        try fetchBookRecord(db: db, id: bookId, instanceId: instanceId)?.downloadStatus
      }) ?? .notDownloaded
  }

  func isBookReadCompleted(bookId: String, instanceId: String) -> Bool {
    (try? read { db in
      try fetchBookRecord(db: db, id: bookId, instanceId: instanceId)?.progressCompleted == true
    }) ?? false
  }

  func fetchPendingBooks(instanceId: String, limit: Int? = nil) -> [Book] {
    (try? read { db in
      var request =
        KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw == "pending")
        .order(KomgaBook.Columns.downloadAt, KomgaBook.Columns.id)
      if let limit {
        request = request.limit(limit)
      }
      return try request.fetchAll(db).map { $0.toBook() }
    }) ?? []
  }

  @discardableResult
  func queueBooksOffline(bookIds: [String], instanceId: String) -> Int {
    guard !bookIds.isEmpty else { return 0 }
    var queuedCount = 0
    var affectedSeriesIds = Set<String>()
    var affectedBookIds: [String] = []
    do {
      try write { db in
        var books = try fetchBooksByIds(db: db, ids: bookIds, instanceId: instanceId)
        let now = Date.now
        for index in books.indices {
          if AppConfig.offlineAutoDeleteRead && books[index].progressCompleted == true {
            continue
          }
          if books[index].downloadStatusRaw == "downloaded" || books[index].downloadStatusRaw == "pending" {
            continue
          }
          books[index].downloadStatusRaw = "pending"
          books[index].downloadError = nil
          books[index].downloadAt = now.addingTimeInterval(Double(index) * 0.001)
          try save(books[index], db: db)
          queuedCount += 1
          affectedSeriesIds.insert(books[index].seriesId)
          affectedBookIds.append(books[index].bookId)
        }

        for seriesId in affectedSeriesIds {
          syncSeriesDownloadStatus(db: db, seriesId: seriesId, instanceId: instanceId)
        }
        syncReadListsContainingBooksInTransaction(db: db, bookIds: affectedBookIds, instanceId: instanceId)
      }
    } catch {
      logger.error("Failed to queue books offline: \(error)")
    }
    return queuedCount
  }

  func fetchDownloadQueueSummary(instanceId: String) -> DownloadQueueSummary {
    DownloadQueueSummary(
      downloadingCount: fetchBooksCount(instanceId: instanceId, status: "downloading"),
      pendingCount: fetchBooksCount(instanceId: instanceId, status: "pending"),
      failedCount: fetchBooksCount(instanceId: instanceId, status: "failed")
    )
  }

  func fetchDownloadedBooksCount(instanceId: String) -> Int {
    fetchBooksCount(instanceId: instanceId, status: "downloaded")
  }

  /// Offline books aggregate for the scope caption and content chip: the count
  /// covers the books the offline list shows, the size sums downloaded books
  /// only — pending books have no data yet.
  func fetchOfflineBooksStats(instanceId: String, libraryIds: [String]) -> (count: Int, sizeBytes: Int64) {
    (try? read { db in
      var sql = """
        SELECT COUNT(*), COALESCE(SUM(CASE WHEN download_status_raw = 'downloaded' THEN size_bytes END), 0)
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ? AND \(Self.offlineBooksSQLPredicate)
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
      guard let row = try Row.fetchOne(db, sql: sql, arguments: arguments) else { return (0, 0) }
      let count: Int = row[0]
      let sizeBytes: Int64 = row[1]
      return (count, sizeBytes)
    }) ?? (0, 0)
  }

  /// Downloaded-series count for the offline content chip.
  func fetchDownloadedSeriesCount(instanceId: String, libraryIds: [String]) -> Int {
    (try? read { db in
      var sql = """
        SELECT COUNT(*) FROM \(KomgaSeries.databaseTableName)
        WHERE instance_id = ? AND \(Self.offlineSeriesSQLPredicate)
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
      return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
    }) ?? 0
  }

  func fetchDownloadedBooks(instanceId: String) -> [Book] {
    (try? read { db in
      try KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw == "downloaded")
        .fetchAll(db)
        .map { $0.toBook() }
    }) ?? []
  }

  /// Raw download status by book ID for books in any active download state. Books
  /// absent from the map have no download intent, so their on-disk data is orphaned.
  func fetchDownloadStatusesByBookId(instanceId: String) -> [String: String] {
    (try? read { db in
      try KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw != "notDownloaded")
        .fetchAll(db)
        .reduce(into: [String: String]()) { $0[$1.bookId] = $1.downloadStatusRaw }
    }) ?? [:]
  }

  func fetchOfflineDownloadedBooksSnapshot(instanceId: String) throws -> OfflineDownloadedBooksSnapshot {
    guard !instanceId.isEmpty else { return .empty }
    return try read { db in
      let downloadedBooks =
        try KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw == "downloaded")
        .fetchAll(db)
      guard !downloadedBooks.isEmpty else { return .empty }

      let downloadedLibraryIds = Array(Set(downloadedBooks.map(\.libraryId)))
      let downloadedSeriesIds = Array(Set(downloadedBooks.map(\.seriesId)))
      let libraryMap = Dictionary(
        uniqueKeysWithValues: try fetchLibraryRecords(
          db: db,
          instanceId: instanceId,
          libraryIds: downloadedLibraryIds
        ).map { ($0.libraryId, $0.name) }
      )
      let seriesMap = Dictionary(
        uniqueKeysWithValues: try fetchSeriesByIds(
          db: db,
          ids: downloadedSeriesIds,
          instanceId: instanceId
        ).map { ($0.seriesId, $0) }
      )
      let libraryBooksMap = Dictionary(grouping: downloadedBooks) { $0.libraryId }
      var libraryGroups: [OfflineDownloadedLibraryGroup] = []

      for (libraryId, libraryBooks) in libraryBooksMap {
        let oneshotBooks = libraryBooks.filter(\.oneshot)
          .map(Self.makeOfflineDownloadedBookItem)
          .sorted {
            $0.oneshotTitle.localizedCaseInsensitiveCompare($1.oneshotTitle) == .orderedAscending
          }

        let seriesBooksMap = Dictionary(grouping: libraryBooks.filter { !$0.oneshot }) { $0.seriesId }
        var seriesGroups: [OfflineDownloadedSeriesGroup] = []
        for (seriesId, seriesBooks) in seriesBooksMap {
          let bookItems =
            seriesBooks
            .map(Self.makeOfflineDownloadedBookItem)
            .sorted {
              if $0.metaNumberSort != $1.metaNumberSort {
                return $0.metaNumberSort < $1.metaNumberSort
              }
              return $0.id < $1.id
            }
          seriesGroups.append(
            OfflineDownloadedSeriesGroup(
              id: seriesId,
              name: seriesMap[seriesId]?.name ?? bookItems.first?.seriesTitle,
              books: bookItems
            )
          )
        }
        seriesGroups.sort {
          ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }

        libraryGroups.append(
          OfflineDownloadedLibraryGroup(
            id: libraryId,
            name: libraryMap[libraryId],
            seriesGroups: seriesGroups,
            oneshotBooks: oneshotBooks
          )
        )
      }

      libraryGroups.sort {
        ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
      }
      return OfflineDownloadedBooksSnapshot(libraryGroups: libraryGroups)
    }
  }

  func fetchOfflineEpubBookIdsMissingProgression(instanceId: String) async -> [String] {
    guard
      let results = try? read({ db in
        try KomgaBook.fetchAll(
          db,
          sql: """
            SELECT *
            FROM \(KomgaBook.databaseTableName)
            WHERE instance_id = ?
            AND download_status_raw = 'downloaded'
            AND media_profile = 'EPUB'
            AND COALESCE(progress_page, 0) > 0
            """,
          arguments: [instanceId]
        )
      })
    else {
      return []
    }
    var bookIds: [String] = []
    for book in results {
      if case .unknown = await decodeStoredEpubProgressionState(book.epubProgressionRaw) {
        bookIds.append(book.bookId)
      }
    }
    return bookIds
  }

  /// Returns the `modified` timestamp of the cached Readium locator for each
  /// requested book that is a downloaded EPUB. A nil timestamp means no usable
  /// locator is cached (never fetched or recorded as missing).
  func fetchDownloadedEpubProgressionModifiedDates(
    instanceId: String,
    bookIds: [String]
  ) async -> [(bookId: String, progressionModified: Date?)] {
    guard !bookIds.isEmpty else { return [] }
    guard
      let results = try? read({ db in
        try KomgaBook
          .filter(KomgaBook.Columns.instanceId == instanceId)
          .filter(bookIds.contains(KomgaBook.Columns.bookId))
          .filter(KomgaBook.Columns.downloadStatusRaw == "downloaded")
          .filter(KomgaBook.Columns.mediaProfile == MediaProfile.epub.rawValue)
          .fetchAll(db)
      })
    else {
      return []
    }
    var checkpoints: [(bookId: String, progressionModified: Date?)] = []
    checkpoints.reserveCapacity(results.count)
    for book in results {
      if case .available(let progression) = await decodeStoredEpubProgressionState(
        book.epubProgressionRaw
      ) {
        checkpoints.append((book.bookId, progression.modified))
      } else {
        checkpoints.append((book.bookId, nil))
      }
    }
    return checkpoints
  }

  func fetchReadBooksEligibleForAutoDelete(instanceId: String) -> [(id: String, seriesId: String)] {
    (try? read { db in
      let now = Date.now
      let books = try KomgaBook.fetchAll(
        db,
        sql: """
            SELECT *
            FROM \(KomgaBook.databaseTableName)
            WHERE instance_id = ?
            AND download_status_raw = 'downloaded'
            AND progress_completed = 1
          """,
        arguments: [instanceId]
      )
      guard !books.isEmpty else { return [] }
      let seriesById = Dictionary(
        uniqueKeysWithValues: try fetchSeriesByIds(
          db: db,
          ids: Array(Set(books.map(\.seriesId))),
          instanceId: instanceId
        ).map { ($0.seriesId, $0) }
      )
      let readListSources = try fetchReadListsAndMembershipsContainingBooks(
        db: db,
        instanceId: instanceId,
        bookIds: books.map(\.bookId)
      )
      let protectionIndex = OfflineProtectionIndex(
        books: try fetchBooks(db: db, instanceId: instanceId),
        series: Array(seriesById.values),
        readLists: readListSources.readLists,
        readListMemberships: readListSources.memberships
      )

      return books.compactMap { book in
        if let downloadAt = book.downloadAt, now.timeIntervalSince(downloadAt) < 300 {
          return nil
        }
        if protectionIndex.isProtected(book) {
          return nil
        }
        return (id: book.bookId, seriesId: book.seriesId)
      }
    }) ?? []
  }

  func hasReadBooksEligibleForAutoDelete(instanceId: String) -> Bool {
    !fetchReadBooksEligibleForAutoDelete(instanceId: instanceId).isEmpty
  }
}

extension DatabaseOperator {
  func fetchKeepReadingBooksForWidget(
    instanceId: String,
    libraryIds: [String],
    limit: Int
  ) -> [Book] {
    (try? read { db in
      var sql = """
        SELECT *
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
        AND progress_read_date IS NOT NULL
        AND progress_completed = 0
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
      sql += "\nORDER BY progress_read_date DESC, id ASC"
      sql += "\nLIMIT ?"
      arguments += StatementArguments([limit])
      return try KomgaBook.fetchAll(db, sql: sql, arguments: arguments).map { $0.toBook() }
    }) ?? []
  }

  func fetchBooksForWidget(bookIds: [String], instanceId: String) -> [Book] {
    (try? read { db in
      try fetchBooksByIds(db: db, ids: bookIds, instanceId: instanceId).map { $0.toBook() }
    }) ?? []
  }

  func fetchRecentlyAddedBooksForWidget(
    instanceId: String,
    libraryIds: [String],
    limit: Int
  ) -> [Book] {
    (try? read { db in
      var sql = """
        SELECT *
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
      sql += "\nORDER BY created DESC, id ASC"
      sql += "\nLIMIT ?"
      arguments += StatementArguments([limit])
      return try KomgaBook.fetchAll(db, sql: sql, arguments: arguments).map { $0.toBook() }
    }) ?? []
  }

  func fetchRecentlyUpdatedSeriesForWidget(
    instanceId: String,
    libraryIds: [String],
    limit: Int
  ) -> [Series] {
    (try? read { db in
      var sql = """
        SELECT *
        FROM \(KomgaSeries.databaseTableName)
        WHERE instance_id = ?
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
      sql += "\nORDER BY last_modified DESC, id ASC"
      sql += "\nLIMIT ?"
      arguments += StatementArguments([limit])
      return try KomgaSeries.fetchAll(db, sql: sql, arguments: arguments).map { $0.toSeries() }
    }) ?? []
  }

  func fetchSeriesForWidget(seriesIds: [String], instanceId: String) -> [Series] {
    (try? read { db in
      try fetchSeriesByIds(db: db, ids: seriesIds, instanceId: instanceId).map { $0.toSeries() }
    }) ?? []
  }

  func fetchBooksWithReadProgressForStats(instanceId: String, libraryId: String?) -> [Book] {
    (try? read { db in
      var sql = """
        SELECT *
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
        AND (progress_page IS NOT NULL OR progress_completed IS NOT NULL OR progress_read_date IS NOT NULL)
        """
      var arguments: StatementArguments = [instanceId]

      if let libraryId {
        sql += "\nAND library_id = ?"
        arguments += StatementArguments([libraryId])
      }

      return try KomgaBook.fetchAll(db, sql: sql, arguments: arguments).map { $0.toBook() }
    }) ?? []
  }

  func fetchSeriesByIdsForStats(instanceId: String, seriesIds: [String]) -> [Series] {
    (try? read { db in
      try fetchSeriesByIds(db: db, ids: seriesIds, instanceId: instanceId).map { $0.toSeries() }
    }) ?? []
  }

  func fetchFailedBooksCount(instanceId: String) -> Int {
    fetchBooksCount(instanceId: instanceId, status: "failed")
  }

  func fetchTotalBooksCount(instanceId: String, libraryId: String? = nil) -> Int {
    (try? read { db in
      var sql = """
        SELECT COUNT(*)
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
        """
      var arguments: StatementArguments = [instanceId]

      if let libraryId {
        sql += "\nAND library_id = ?"
        arguments += StatementArguments([libraryId])
      }

      return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
    }) ?? 0
  }

  func fetchTotalSeriesCount(instanceId: String) -> Int {
    (try? read { db in
      try KomgaSeries
        .filter(KomgaSeries.Columns.instanceId == instanceId)
        .fetchCount(db)
    }) ?? 0
  }

  func queuePendingProgress(
    instanceId: String,
    bookId: String,
    page: Int,
    completed: Bool,
    progressionData: Data? = nil
  ) {
    do {
      try write { db in
        let compositeId = CompositeID.generate(instanceId: instanceId, id: bookId)
        if var existing = try PendingProgress.fetchOne(db, key: compositeId) {
          existing.page = page
          existing.completed = completed
          existing.createdAt = Date()
          existing.progressionData = progressionData
          try save(existing, db: db)
          logger.debug("Updated pending progress id=\(existing.id)")
        } else {
          let pending = PendingProgress(
            instanceId: instanceId,
            bookId: bookId,
            page: page,
            completed: completed,
            progressionData: progressionData
          )
          try save(pending, db: db)
          logger.debug("Queued pending progress id=\(pending.id)")
        }
      }
    } catch {
      logger.error("Failed to queue pending progress: \(error)")
    }
  }

  func fetchPendingProgress(instanceId: String, limit: Int? = nil) -> [PendingProgressSummary] {
    (try? read { db in
      var request =
        PendingProgress
        .filter(Column("instance_id") == instanceId)
        .order(Column("created_at"), Column("id"))
      if let limit {
        request = request.limit(limit)
      }
      return try request.fetchAll(db).map {
        PendingProgressSummary(
          id: $0.id,
          instanceId: $0.instanceId,
          bookId: $0.bookId,
          page: $0.page,
          completed: $0.completed,
          createdAt: $0.createdAt,
          progressionData: $0.progressionData
        )
      }
    }) ?? []
  }

  func deletePendingProgress(id: String) {
    _ = try? write { db in
      try PendingProgress.deleteOne(db, key: id)
    }
  }
}

extension DatabaseOperator {
  func fetchLibraryRecords(db: Database, instanceId: String) throws -> [KomgaLibrary] {
    try KomgaLibrary
      .filter(KomgaLibrary.Columns.instanceId == instanceId)
      .fetchAll(db)
  }

  func fetchLibraryRecords(db: Database, instanceId: String, libraryIds: [String]) throws -> [KomgaLibrary] {
    guard !libraryIds.isEmpty else { return [] }
    var sql = """
      SELECT *
      FROM \(KomgaLibrary.databaseTableName)
      WHERE instance_id = ?
      """
    var arguments: StatementArguments = [instanceId]
    Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
    return try KomgaLibrary.fetchAll(db, sql: sql, arguments: arguments)
  }

  func fetchBooksCount(instanceId: String, status: String) -> Int {
    (try? read { db in
      try KomgaBook
        .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.downloadStatusRaw == status)
        .fetchCount(db)
    }) ?? 0
  }

  func syncReadListsContainingBooksInTransaction(
    db: Database,
    bookIds: [String],
    instanceId: String,
    excludingReadListId: String? = nil
  ) {
    guard !bookIds.isEmpty else { return }
    guard
      let containingReadListIds = try? fetchReadListIdsContainingBooks(db: db, instanceId: instanceId, bookIds: bookIds)
    else { return }
    let readListIds = containingReadListIds.filter { readListId in
      if let excludingReadListId {
        return readListId != excludingReadListId
      }
      return true
    }
    guard !readListIds.isEmpty else { return }
    guard var readLists = try? fetchReadListsByIds(db: db, ids: readListIds, instanceId: instanceId) else { return }
    for index in readLists.indices {
      syncReadListDownloadStatus(db: db, readList: &readLists[index])
      try? save(readLists[index], db: db)
    }
  }

  nonisolated static func makeSidebarLibraryItem(_ library: KomgaLibrary) -> SidebarLibraryItem {
    SidebarLibraryItem(
      libraryId: library.libraryId,
      name: library.name,
      fileSize: library.fileSize,
      booksCount: library.booksCount,
      seriesCount: library.seriesCount,
      sidecarsCount: library.sidecarsCount,
      collectionsCount: library.collectionsCount,
      readlistsCount: library.readlistsCount
    )
  }

  nonisolated static func makeCustomFontDisplayItem(_ font: CustomFont) -> CustomFontDisplayItem {
    CustomFontDisplayItem(
      name: font.name,
      path: font.path,
      fileName: font.fileName,
      fileSize: font.fileSize
    )
  }

  nonisolated static func makeServerDisplayItem(_ instance: KomgaInstance) -> ServerDisplayItem {
    ServerDisplayItem(
      id: instance.id,
      name: instance.name,
      serverURL: instance.serverURL,
      username: instance.username,
      authToken: instance.authToken,
      isAdmin: instance.isAdmin,
      authMethod: instance.resolvedAuthMethod,
      protected: instance.protected,
      lastUsedAt: instance.lastUsedAt
    )
  }

  nonisolated static func defaultName(serverURL: String, username: String) -> String {
    if let host = URL(string: serverURL)?.host, !host.isEmpty {
      return host
    }
    return serverURL
  }

  nonisolated static func resolvedName(displayName: String?, serverURL: String, username: String) -> String {
    if let displayName, !displayName.isEmpty {
      return displayName
    }
    return defaultName(serverURL: serverURL, username: username)
  }

  nonisolated static func makeOfflineDownloadedBookItem(_ book: KomgaBook) -> OfflineDownloadedBookItem {
    OfflineDownloadedBookItem(
      id: book.id,
      instanceId: book.instanceId,
      bookId: book.bookId,
      seriesId: book.seriesId,
      libraryId: book.libraryId,
      bookName: book.name,
      seriesTitle: book.seriesTitle,
      metaNumber: book.metaNumber,
      metaTitle: book.metaTitle,
      metaNumberSort: book.metaNumberSort,
      downloadedSize: book.downloadedSize,
      isReadCompleted: book.readProgress?.completed == true
    )
  }
}
