//
// DatabaseOperator+Series.swift
//
//

import Foundation
import GRDB

extension DatabaseOperator {
  func fetchSeriesDisplayItem(seriesId: String, instanceId: String) throws -> SeriesDisplayItem? {
    guard !seriesId.isEmpty, !instanceId.isEmpty else { return nil }
    return try read { db in
      try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId).map(Self.makeSeriesDisplayItem)
    }
  }

  func fetchBrowseSeriesIds(
    instanceId: String,
    libraryIds: [String]?,
    searchText: String,
    browseOpts: SeriesBrowseOptions,
    offset: Int,
    limit: Int,
    offlineOnly: Bool = false
  ) -> [String] {
    guard !instanceId.isEmpty else { return [] }
    guard limit > 0 else { return [] }
    return
      (try? read { db in
        try fetchBrowseSeriesRecords(
          db: db,
          instanceId: instanceId,
          libraryIds: libraryIds ?? [],
          searchText: searchText,
          browseOpts: browseOpts,
          offset: offset,
          limit: limit,
          offlineOnly: offlineOnly
        ).map(\.seriesId)
      }) ?? []
  }

  func fetchCollectionSeriesIds(
    collectionId: String,
    browseOpts: CollectionSeriesBrowseOptions,
    page: Int,
    size: Int
  ) -> [String] {
    let instanceId = AppConfig.current.instanceId
    return
      (try? read { db in
        guard let collection = try fetchCollectionRecord(db: db, id: collectionId, instanceId: instanceId) else {
          return []
        }
        let series = try fetchSeriesByIds(db: db, ids: collection.seriesIds, instanceId: instanceId)
          .filter { Self.matchesSeries($0, collectionBrowseOpts: browseOpts) }
        return Self.paginate(series, offset: page * size, limit: size).map(\.seriesId)
      }) ?? []
  }

  func fetchDashboardOfflineSeriesIds(
    section: DashboardSection,
    libraryIds: [String],
    offset: Int,
    limit: Int
  ) -> [String] {
    guard limit > 0 else { return [] }
    let instanceId = AppConfig.current.instanceId
    return
      (try? read { db in
        var sql = """
          SELECT series_id
          FROM \(KomgaSeries.databaseTableName)
          WHERE instance_id = ?
          """
        var arguments: StatementArguments = [instanceId]

        if !libraryIds.isEmpty {
          let placeholders = Array(repeating: "?", count: libraryIds.count).joined(separator: ", ")
          sql += "\nAND library_id IN (\(placeholders))"
          arguments += StatementArguments(libraryIds)
        }

        switch section {
        case .recentlyAddedSeries:
          sql += "\nAND oneshot = 0"
          sql += "\nORDER BY created DESC, id ASC"
        case .recentlyUpdatedSeries:
          sql += "\nAND oneshot = 0"
          sql += "\nAND created != last_modified"
          sql += "\nORDER BY last_modified DESC, id ASC"
        default:
          return []
        }

        sql += "\nLIMIT ? OFFSET ?"
        arguments += StatementArguments([limit, max(0, offset)])

        return try String.fetchAll(db, sql: sql, arguments: arguments)
      }) ?? []
  }

  func upsertSeries(dto: Series, instanceId: String) {
    do {
      try write { db in
        let compositeId = CompositeID.generate(instanceId: instanceId, id: dto.id)
        if var existing = try KomgaSeries.fetchOne(db, key: compositeId) {
          applySeries(dto: dto, to: &existing)
          try save(existing, db: db)
        } else {
          let newSeries = KomgaSeries(
            id: compositeId,
            seriesId: dto.id,
            libraryId: dto.libraryId,
            instanceId: instanceId,
            name: dto.name,
            url: dto.url,
            created: dto.created,
            lastModified: dto.lastModified,
            booksCount: dto.booksCount,
            booksReadCount: dto.booksReadCount,
            booksUnreadCount: dto.booksUnreadCount,
            booksInProgressCount: dto.booksInProgressCount,
            metadata: dto.metadata,
            booksMetadata: dto.booksMetadata,
            isUnavailable: dto.deleted,
            oneshot: dto.oneshot
          )
          try save(newSeries, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert series: \(error)")
    }
  }

  func deleteSeries(id: String, instanceId: String) {
    do {
      _ = try write { db in
        try KomgaSeries.deleteOne(db, key: CompositeID.generate(instanceId: instanceId, id: id))
      }
    } catch {
      logger.error("Failed to delete series: \(error)")
    }
  }

  @discardableResult
  func markSeriesUnavailable(seriesId: String, instanceId: String) -> Bool {
    do {
      return try write { db in
        guard var series = try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else {
          return false
        }
        guard !series.isUnavailable else { return true }
        series.isUnavailable = true
        try save(series, db: db)
        return true
      }
    } catch {
      logger.error("Failed to mark series unavailable: \(error)")
      return false
    }
  }

  func upsertSeriesList(_ seriesList: [Series], instanceId: String) {
    do {
      try write { db in
        let existingSeries = try fetchSeriesByIds(db: db, ids: seriesList.map(\.id), instanceId: instanceId)
        let existingById = Dictionary(uniqueKeysWithValues: existingSeries.map { ($0.seriesId, $0) })

        for series in seriesList {
          var record =
            existingById[series.id]
            ?? KomgaSeries(
              id: CompositeID.generate(instanceId: instanceId, id: series.id),
              seriesId: series.id,
              libraryId: series.libraryId,
              instanceId: instanceId,
              name: series.name,
              url: series.url,
              created: series.created,
              lastModified: series.lastModified,
              booksCount: series.booksCount,
              booksReadCount: series.booksReadCount,
              booksUnreadCount: series.booksUnreadCount,
              booksInProgressCount: series.booksInProgressCount,
              metadata: series.metadata,
              booksMetadata: series.booksMetadata,
              isUnavailable: series.deleted,
              oneshot: series.oneshot
            )
          applySeries(dto: series, to: &record)
          try save(record, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert series list: \(error)")
    }
  }

  func deleteSeriesNotIn(_ seriesIds: Set<String>, instanceId: String) -> Int {
    (try? write { db in
      var deletedCount = 0
      var lastScannedId: String?

      while true {
        var request =
          KomgaSeries
          .filter(KomgaSeries.Columns.instanceId == instanceId)
          .order(KomgaSeries.Columns.id)
          .limit(Self.recordFetchChunkSize)

        if let lastScannedId {
          request = request.filter(KomgaSeries.Columns.id > lastScannedId)
        }

        let batch = try request.fetchAll(db)
        guard !batch.isEmpty else { break }
        lastScannedId = batch.last?.id

        for series in batch where !seriesIds.contains(series.seriesId) {
          try KomgaSeries.deleteOne(db, key: series.id)
          deletedCount += 1
        }
      }

      return deletedCount
    }) ?? 0
  }

  func fetchSeries(id: String) async -> Series? {
    try? read { db in
      try fetchSeriesRecord(db: db, id: id)?.toSeries()
    }
  }

  /// Series id of the book's series only when that series has no local row yet.
  func fetchMissingSeriesId(bookId: String, instanceId: String) -> String? {
    try? read { db in
      guard let book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId),
        try fetchSeriesRecord(db: db, id: book.seriesId, instanceId: instanceId) == nil
      else { return nil }
      return book.seriesId
    }
  }

  func updateSeriesCollectionIds(seriesId: String, collectionIds: [String], instanceId: String) {
    do {
      try write { db in
        guard var series = try fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else {
          return
        }
        series.collectionIds = collectionIds
        try save(series, db: db)
      }
    } catch {
      logger.error("Failed to update series collection ids: \(error)")
    }
  }

  func updateBookReadListIds(bookId: String, readListIds: [String], instanceId: String) {
    do {
      try write { db in
        guard var book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else { return }
        book.readListIds = readListIds
        try save(book, db: db)
      }
    } catch {
      logger.error("Failed to update book read-list ids: \(error)")
    }
  }
}

extension DatabaseOperator {
  func fetchSeriesByIds(db: Database, ids: [String], instanceId: String) throws -> [KomgaSeries] {
    guard !ids.isEmpty else { return [] }
    let uniqueCompositeIds = Array(Set(ids.map { CompositeID.generate(instanceId: instanceId, id: $0) }))
    var series: [KomgaSeries] = []

    for start in stride(from: 0, to: uniqueCompositeIds.count, by: Self.recordFetchChunkSize) {
      let end = min(start + Self.recordFetchChunkSize, uniqueCompositeIds.count)
      let chunk = Array(uniqueCompositeIds[start..<end])
      let fetched = try KomgaSeries.fetchAll(db, keys: chunk)
      series.append(contentsOf: fetched)
    }

    return Self.orderedByIds(series, ids: ids, id: \.seriesId)
  }

  func fetchCollectionSeries(
    db: Database,
    collectionId: String,
    instanceId: String,
    page: Int,
    size: Int,
    browseOpts: CollectionSeriesBrowseOptions = CollectionSeriesBrowseOptions()
  ) throws -> [Series] {
    guard let collection = try fetchCollectionRecord(db: db, id: collectionId, instanceId: instanceId) else {
      return []
    }
    let series = try fetchSeriesByIds(db: db, ids: collection.seriesIds, instanceId: instanceId)
      .filter { Self.matchesSeries($0, collectionBrowseOpts: browseOpts) }
    return Self.paginate(series, offset: page * size, limit: size).map { $0.toSeries() }
  }

  func applySeries(dto: Series, to existing: inout KomgaSeries) {
    let metadataRaw = RawCodableStore.encode(dto.metadata)
    let booksMetadataRaw = RawCodableStore.encode(dto.booksMetadata)

    if existing.name != dto.name { existing.name = dto.name }
    if existing.url != dto.url { existing.url = dto.url }
    if existing.lastModified != dto.lastModified { existing.lastModified = dto.lastModified }
    if existing.booksCount != dto.booksCount { existing.booksCount = dto.booksCount }
    if existing.booksReadCount != dto.booksReadCount {
      existing.booksReadCount = dto.booksReadCount
    }
    if existing.booksUnreadCount != dto.booksUnreadCount {
      existing.booksUnreadCount = dto.booksUnreadCount
    }
    if existing.booksInProgressCount != dto.booksInProgressCount {
      existing.booksInProgressCount = dto.booksInProgressCount
    }
    if metadataRaw == nil || existing.metadataRaw != metadataRaw {
      existing.updateMetadata(dto.metadata, raw: metadataRaw)
    }
    if booksMetadataRaw == nil || existing.booksMetadataRaw != booksMetadataRaw {
      existing.updateBooksMetadata(dto.booksMetadata, raw: booksMetadataRaw)
    }
    if existing.isUnavailable != dto.deleted { existing.isUnavailable = dto.deleted }
    if existing.oneshot != dto.oneshot { existing.oneshot = dto.oneshot }
  }

  func syncSeriesReadingStatus(db: Database, seriesId: String, instanceId: String) {
    guard var series = try? fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else { return }
    let books = (try? fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)) ?? []
    var read = 0
    var inProgress = 0
    var unread = 0
    for book in books {
      switch readingStatus(progressCompleted: book.progressCompleted, progressPage: book.progressPage) {
      case 2: read += 1
      case 1: inProgress += 1
      default: unread += 1
      }
    }
    series.booksReadCount = read
    series.booksInProgressCount = inProgress
    series.booksUnreadCount = unread
    try? save(series, db: db)
  }

  func syncSeriesReadingStatus(seriesId: String, instanceId: String) {
    try? write { db in
      syncSeriesReadingStatus(db: db, seriesId: seriesId, instanceId: instanceId)
    }
  }

  nonisolated static func makeSeriesDisplayItem(_ series: KomgaSeries) -> SeriesDisplayItem {
    SeriesDisplayItem(
      instanceId: series.instanceId,
      series: series.toSeries(),
      downloadStatus: series.downloadStatus,
      offlinePolicy: series.offlinePolicy,
      offlinePolicyLimit: series.offlinePolicyLimit,
      collectionIds: series.collectionIds
    )
  }

  nonisolated static func filteredBrowseSeries(
    _ series: [KomgaSeries],
    libraryIds: [String]?,
    searchText: String,
    browseOpts: SeriesBrowseOptions,
    offlineOnly: Bool = false
  ) -> [KomgaSeries] {
    let libraryIds = libraryIds ?? []
    return sortSeries(
      series.filter { item in
        if !libraryIds.isEmpty && !libraryIds.contains(item.libraryId) { return false }
        if !searchText.isEmpty
          && !item.name.localizedStandardContains(searchText)
          && !item.metaTitle.localizedStandardContains(searchText)
        {
          return false
        }
        if offlineOnly
          && item.downloadedBooks <= 0
          && item.pendingBooks <= 0
          && item.downloadStatusRaw != "downloaded"
        {
          return false
        }
        return matchesSeries(item, browseOpts: browseOpts)
      },
      sort: browseOpts.sortString
    )
  }

  nonisolated static func matchesSeries(_ series: KomgaSeries, browseOpts: SeriesBrowseOptions) -> Bool {
    if let deletedState = browseOpts.deletedFilter.effectiveBool, series.isUnavailable != deletedState {
      return false
    }
    if let oneshotState = browseOpts.oneshotFilter.effectiveBool, series.oneshot != oneshotState {
      return false
    }
    if let completeState = browseOpts.completeFilter.effectiveBool,
      (series.metadata?.totalBookCount == series.booksCount) != completeState
    {
      return false
    }
    let status = series.readStatus
    if !browseOpts.includeReadStatuses.isEmpty && !browseOpts.includeReadStatuses.contains(status) {
      return false
    }
    if !browseOpts.excludeReadStatuses.isEmpty && browseOpts.excludeReadStatuses.contains(status) {
      return false
    }
    if !browseOpts.includeSeriesStatuses.isEmpty || !browseOpts.excludeSeriesStatuses.isEmpty {
      if let seriesStatus = SeriesStatus.fromAPIValue(series.metadata?.status) {
        if !browseOpts.includeSeriesStatuses.isEmpty && !browseOpts.includeSeriesStatuses.contains(seriesStatus) {
          return false
        }
        if !browseOpts.excludeSeriesStatuses.isEmpty && browseOpts.excludeSeriesStatuses.contains(seriesStatus) {
          return false
        }
      }
    }
    return matchesSeriesMetadataFilter(series: series, filter: browseOpts.metadataFilter)
  }

  nonisolated static func matchesSeries(
    _ series: KomgaSeries,
    collectionBrowseOpts: CollectionSeriesBrowseOptions
  ) -> Bool {
    if let deletedState = collectionBrowseOpts.deletedFilter.effectiveBool, series.isUnavailable != deletedState {
      return false
    }
    if let oneshotState = collectionBrowseOpts.oneshotFilter.effectiveBool, series.oneshot != oneshotState {
      return false
    }
    if let completeState = collectionBrowseOpts.completeFilter.effectiveBool,
      (series.metadata?.totalBookCount == series.booksCount) != completeState
    {
      return false
    }
    let status = series.readStatus
    if !collectionBrowseOpts.includeReadStatuses.isEmpty && !collectionBrowseOpts.includeReadStatuses.contains(status) {
      return false
    }
    if !collectionBrowseOpts.excludeReadStatuses.isEmpty && collectionBrowseOpts.excludeReadStatuses.contains(status) {
      return false
    }
    if !collectionBrowseOpts.includeSeriesStatuses.isEmpty || !collectionBrowseOpts.excludeSeriesStatuses.isEmpty {
      if let seriesStatus = SeriesStatus.fromAPIValue(series.metadata?.status) {
        if !collectionBrowseOpts.includeSeriesStatuses.isEmpty
          && !collectionBrowseOpts.includeSeriesStatuses.contains(seriesStatus)
        {
          return false
        }
        if !collectionBrowseOpts.excludeSeriesStatuses.isEmpty
          && collectionBrowseOpts.excludeSeriesStatuses.contains(seriesStatus)
        {
          return false
        }
      }
    }
    return matchesSeriesMetadataFilter(series: series, filter: collectionBrowseOpts.metadataFilter)
  }

  func fetchBrowseSeriesRecords(
    db: Database,
    instanceId: String,
    libraryIds: [String],
    searchText: String,
    browseOpts: SeriesBrowseOptions,
    offset: Int,
    limit: Int,
    offlineOnly: Bool
  ) throws -> [KomgaSeries] {
    let safeOffset = max(0, offset)
    if browseOpts.sortString == "random" {
      let candidates = try fetchBrowseSeriesSQLCandidates(
        db: db,
        instanceId: instanceId,
        libraryIds: libraryIds,
        searchText: searchText,
        browseOpts: browseOpts,
        offset: nil,
        limit: nil,
        offlineOnly: offlineOnly
      )
      return Self.paginate(
        Self.filteredBrowseSeries(
          candidates,
          libraryIds: nil,
          searchText: searchText,
          browseOpts: browseOpts,
          offlineOnly: offlineOnly
        ),
        offset: safeOffset,
        limit: limit
      )
    }

    let requiresResidualFilter =
      browseOpts.completeFilter.isActive
      || !browseOpts.includeSeriesStatuses.isEmpty
      || !browseOpts.excludeSeriesStatuses.isEmpty

    if !requiresResidualFilter {
      return try fetchBrowseSeriesSQLCandidates(
        db: db,
        instanceId: instanceId,
        libraryIds: libraryIds,
        searchText: searchText,
        browseOpts: browseOpts,
        offset: safeOffset,
        limit: limit,
        offlineOnly: offlineOnly
      )
    }

    var matched: [KomgaSeries] = []
    var skipped = 0
    var sqlOffset = 0

    while matched.count < limit {
      let chunk = try fetchBrowseSeriesSQLCandidates(
        db: db,
        instanceId: instanceId,
        libraryIds: libraryIds,
        searchText: searchText,
        browseOpts: browseOpts,
        offset: sqlOffset,
        limit: Self.recordFetchChunkSize,
        offlineOnly: offlineOnly
      )
      guard !chunk.isEmpty else { break }
      sqlOffset += chunk.count

      for item in chunk where Self.matchesSeries(item, browseOpts: browseOpts) {
        if skipped < safeOffset {
          skipped += 1
        } else {
          matched.append(item)
          if matched.count == limit { break }
        }
      }
    }

    return matched
  }

  func fetchBrowseSeriesSQLCandidates(
    db: Database,
    instanceId: String,
    libraryIds: [String],
    searchText: String,
    browseOpts: SeriesBrowseOptions,
    offset: Int?,
    limit: Int?,
    offlineOnly: Bool
  ) throws -> [KomgaSeries] {
    var sql = """
      SELECT *
      FROM \(KomgaSeries.databaseTableName)
      WHERE instance_id = ?
      """
    var arguments: StatementArguments = [instanceId]

    Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)
    Self.appendSeriesBrowseSQLFilters(
      searchText: searchText,
      browseOpts: browseOpts,
      offlineOnly: offlineOnly,
      sql: &sql,
      arguments: &arguments
    )

    if let orderSQL = Self.seriesBrowseOrderSQL(sort: browseOpts.sortString) {
      sql += "\nORDER BY \(orderSQL)"
    }

    if let limit {
      sql += "\nLIMIT ? OFFSET ?"
      arguments += StatementArguments([limit, max(0, offset ?? 0)])
    }

    return try KomgaSeries.fetchAll(db, sql: sql, arguments: arguments)
  }

  /// SQL predicate for series the offline list shows; shared with the
  /// downloaded-series count query so the chip count cannot drift from the list.
  nonisolated static let offlineSeriesSQLPredicate =
    "(downloaded_books > 0 OR pending_books > 0 OR download_status_raw = 'downloaded')"

  nonisolated static func appendSeriesBrowseSQLFilters(
    searchText: String,
    browseOpts: SeriesBrowseOptions,
    offlineOnly: Bool,
    sql: inout String,
    arguments: inout StatementArguments
  ) {
    let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSearch.isEmpty {
      let pattern = sqlContainsPattern(trimmedSearch)
      sql += "\nAND (name LIKE ? ESCAPE char(92) OR meta_title LIKE ? ESCAPE char(92))"
      arguments += StatementArguments([pattern, pattern])
    }

    if offlineOnly {
      sql += "\nAND \(offlineSeriesSQLPredicate)"
    }

    if let deletedState = browseOpts.deletedFilter.effectiveBool {
      sql += "\nAND is_unavailable = ?"
      arguments += StatementArguments([deletedState])
    }

    if let oneshotState = browseOpts.oneshotFilter.effectiveBool {
      sql += "\nAND oneshot = ?"
      arguments += StatementArguments([oneshotState])
    }

    appendSeriesReadStatusSQLFilter(
      include: browseOpts.includeReadStatuses,
      exclude: browseOpts.excludeReadStatuses,
      sql: &sql
    )
    appendSeriesMetadataSQLFilter(browseOpts.metadataFilter, sql: &sql, arguments: &arguments)
  }

  nonisolated static func appendSeriesReadStatusSQLFilter(
    include: Set<ReadStatus>,
    exclude: Set<ReadStatus>,
    sql: inout String
  ) {
    if !include.isEmpty {
      let clauses = include.sorted { $0.rawValue < $1.rawValue }.map(seriesReadStatusSQL)
      sql += "\nAND (\(clauses.joined(separator: " OR ")))"
    }

    if !exclude.isEmpty {
      let clauses = exclude.sorted { $0.rawValue < $1.rawValue }.map(seriesReadStatusSQL)
      sql += "\nAND NOT (\(clauses.joined(separator: " OR ")))"
    }
  }

  nonisolated static func seriesReadStatusSQL(_ status: ReadStatus) -> String {
    switch status {
    case .read:
      return "(books_count > 0 AND books_read_count = books_count)"
    case .inProgress:
      return
        "(NOT (books_count > 0 AND books_read_count = books_count) AND (books_read_count > 0 OR books_in_progress_count > 0))"
    case .unread:
      return "(books_read_count <= 0 AND books_in_progress_count <= 0)"
    }
  }

  nonisolated static func appendSeriesMetadataSQLFilter(
    _ filter: MetadataFilterConfig,
    sql: inout String,
    arguments: inout StatementArguments
  ) {
    appendMetadataIndexSQLFilter(
      column: "meta_publisher_index",
      values: filter.publishers,
      logic: filter.publishersLogic,
      sql: &sql,
      arguments: &arguments
    )
    appendMetadataIndexSQLFilter(
      column: "meta_authors_index",
      values: filter.authors,
      logic: filter.authorsLogic,
      sql: &sql,
      arguments: &arguments
    )
    appendMetadataIndexSQLFilter(
      column: "meta_genres_index",
      values: filter.genres,
      logic: filter.genresLogic,
      sql: &sql,
      arguments: &arguments
    )
    appendMetadataIndexSQLFilter(
      column: "meta_tags_index",
      values: filter.tags,
      logic: filter.tagsLogic,
      sql: &sql,
      arguments: &arguments
    )
    appendMetadataIndexSQLFilter(
      column: "meta_language_index",
      values: filter.languages,
      logic: filter.languagesLogic,
      sql: &sql,
      arguments: &arguments
    )
  }

  nonisolated static func seriesBrowseOrderSQL(sort: String) -> String? {
    guard sort != "random" else { return nil }
    let direction = sort.contains("desc") ? "DESC" : "ASC"
    if sort.contains("created") {
      return "created \(direction), id ASC"
    }
    if sort.contains("lastModified") {
      return "last_modified \(direction), id ASC"
    }
    if sort.contains("downloadAt") {
      return "download_at \(direction), id ASC"
    }
    if sort.contains("booksCount") {
      return "books_count \(direction), id ASC"
    }
    return "meta_title_sort \(direction), id ASC"
  }

  nonisolated static func sortSeries(_ series: [KomgaSeries], sort: String) -> [KomgaSeries] {
    if sort == "random" {
      return series.sorted {
        let lhsKey = stableRandomSortKey($0.seriesId)
        let rhsKey = stableRandomSortKey($1.seriesId)
        if lhsKey == rhsKey {
          return $0.seriesId < $1.seriesId
        }
        return lhsKey < rhsKey
      }
    }
    let isAsc = !sort.contains("desc")
    if sort.contains("metadata.titleSort") {
      return series.sorted { isAsc ? $0.metaTitleSort < $1.metaTitleSort : $0.metaTitleSort > $1.metaTitleSort }
    }
    if sort.contains("created") {
      return series.sorted { isAsc ? $0.created < $1.created : $0.created > $1.created }
    }
    if sort.contains("lastModified") {
      return series.sorted { isAsc ? $0.lastModified < $1.lastModified : $0.lastModified > $1.lastModified }
    }
    if sort.contains("downloadAt") {
      return series.sorted {
        isAsc
          ? ($0.downloadAt ?? .distantPast) < ($1.downloadAt ?? .distantPast)
          : ($0.downloadAt ?? .distantPast) > ($1.downloadAt ?? .distantPast)
      }
    }
    if sort.contains("booksCount") {
      return series.sorted { isAsc ? $0.booksCount < $1.booksCount : $0.booksCount > $1.booksCount }
    }
    return series.sorted { isAsc ? $0.metaTitleSort < $1.metaTitleSort : $0.metaTitleSort > $1.metaTitleSort }
  }

  nonisolated static func stableRandomSortKey(_ value: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return hash
  }
}
