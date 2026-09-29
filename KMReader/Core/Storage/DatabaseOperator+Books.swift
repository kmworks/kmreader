//
// DatabaseOperator+Books.swift
//
//

import Foundation
import GRDB

extension DatabaseOperator {
  func fetchBookDisplayItem(
    bookId: String,
    instanceId: String,
    includeOfflineProtection: Bool = false
  ) throws -> BookDisplayItem? {
    guard !bookId.isEmpty, !instanceId.isEmpty else { return nil }
    return try read { db in
      guard let book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else {
        return nil
      }
      return try makeBookDisplayItem(
        db: db,
        book: book,
        includeOfflineProtection: includeOfflineProtection
      )
    }
  }

  func fetchFirstBookDisplayItem(
    seriesId: String,
    instanceId: String,
    includeOfflineProtection: Bool = false
  ) throws -> BookDisplayItem? {
    guard !seriesId.isEmpty, !instanceId.isEmpty else { return nil }
    return try read { db in
      guard
        let book =
          try KomgaBook
          .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.seriesId == seriesId)
          .order(KomgaBook.Columns.metaNumberSort, KomgaBook.Columns.id)
          .fetchOne(db)
      else {
        return nil
      }
      return try makeBookDisplayItem(
        db: db,
        book: book,
        includeOfflineProtection: includeOfflineProtection
      )
    }
  }

  func fetchOfflineProtectionSources(
    instanceId: String,
    bookIds: [String]
  ) throws -> [String: [OfflineProtectionSource]] {
    guard !instanceId.isEmpty, !bookIds.isEmpty else { return [:] }
    return try read { db in
      let targetBooks = try fetchBooksByIds(db: db, ids: bookIds, instanceId: instanceId)
      return try fetchOfflineProtectionSources(
        db: db,
        instanceId: instanceId,
        targetBooks: targetBooks
      )
    }
  }

  func fetchBrowseBookIds(
    instanceId: String,
    libraryIds: [String]?,
    searchText: String,
    browseOpts: BookBrowseOptions,
    offset: Int,
    limit: Int,
    offlineOnly: Bool = false
  ) -> [String] {
    guard !instanceId.isEmpty else { return [] }
    guard limit > 0 else { return [] }
    return
      (try? read { db in
        var sql = """
          SELECT book_id
          FROM \(KomgaBook.databaseTableName)
          WHERE instance_id = ?
          """
        var arguments: StatementArguments = [instanceId]

        Self.appendSQLInFilter(
          column: "library_id",
          values: libraryIds ?? [],
          sql: &sql,
          arguments: &arguments
        )
        Self.appendBookBrowseSQLFilters(
          searchText: searchText,
          browseOpts: browseOpts,
          offlineOnly: offlineOnly,
          sql: &sql,
          arguments: &arguments
        )
        sql += "\nORDER BY \(Self.bookBrowseOrderSQL(sort: browseOpts.sortString))"
        sql += "\nLIMIT ? OFFSET ?"
        arguments += StatementArguments([limit, max(0, offset)])

        return try String.fetchAll(db, sql: sql, arguments: arguments)
      }) ?? []
  }

  func fetchSeriesBookIds(
    seriesId: String,
    browseOpts: BookBrowseOptions,
    page: Int,
    size: Int
  ) -> [String] {
    let instanceId = AppConfig.current.instanceId
    return
      (try? read { db in
        let books = try fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)
        return Self.paginate(
          Self.filteredBrowseBooks(
            books,
            libraryIds: nil,
            searchText: "",
            browseOpts: browseOpts
          ),
          offset: page * size,
          limit: size
        ).map(\.bookId)
      }) ?? []
  }

  func fetchReadListBookIds(
    readListId: String,
    browseOpts: ReadListBookBrowseOptions,
    page: Int,
    size: Int
  ) -> [String] {
    let instanceId = AppConfig.current.instanceId
    return
      (try? read { db in
        guard let readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
          return []
        }
        let books = try fetchBooksByIds(db: db, ids: readList.bookIds, instanceId: instanceId)
        let filtered = books.filter { Self.matchesBook($0, readListBrowseOpts: browseOpts) }
        return Self.paginate(filtered, offset: page * size, limit: size).map(\.bookId)
      }) ?? []
  }

  func fetchDashboardOfflineBookIds(
    section: DashboardSection,
    libraryIds: [String],
    offset: Int,
    limit: Int
  ) -> [String] {
    guard limit > 0 else { return [] }
    let instanceId = AppConfig.current.instanceId
    return
      (try? read { db in
        if section == .onDeck {
          return try fetchDashboardOfflineOnDeckBookIds(
            db: db,
            instanceId: instanceId,
            libraryIds: libraryIds,
            offset: offset,
            limit: limit
          )
        }

        var sql = """
          SELECT book_id
          FROM \(KomgaBook.databaseTableName)
          WHERE instance_id = ?
          """
        var arguments: StatementArguments = [instanceId]

        Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)

        switch section {
        case .keepReading:
          sql += "\nAND progress_read_date IS NOT NULL AND progress_completed = 0"
          sql += "\nORDER BY progress_read_date DESC, id ASC"
        case .recentlyReadBooks:
          sql += "\nAND progress_read_date IS NOT NULL AND progress_completed = 1"
          sql += "\nORDER BY progress_read_date DESC, id ASC"
        case .recentlyReleasedBooks:
          sql += "\nAND meta_release_date > ?"
          arguments += StatementArguments([recentlyReleasedCutoffDateString()])
          sql += "\nORDER BY COALESCE(meta_release_date, '') DESC, id ASC"
        case .recentlyAddedBooks:
          sql += "\nORDER BY created DESC, id ASC"
        default:
          return []
        }

        sql += "\nLIMIT ? OFFSET ?"
        arguments += StatementArguments([limit, max(0, offset)])

        return try String.fetchAll(db, sql: sql, arguments: arguments)
      }) ?? []
  }

  private func fetchDashboardOfflineOnDeckBookIds(
    db: Database,
    instanceId: String,
    libraryIds: [String],
    offset: Int,
    limit: Int
  ) throws -> [String] {
    var sql = """
      WITH on_deck_series AS (
        SELECT
          series_id,
          MAX(progress_read_date) AS most_recent_read_date
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
      """
    var arguments: StatementArguments = [instanceId]

    Self.appendSQLInFilter(column: "library_id", values: libraryIds, sql: &sql, arguments: &arguments)

    sql += """

        GROUP BY series_id
        HAVING
          SUM(CASE WHEN progress_completed = 1 THEN 1 ELSE 0 END) > 0
          AND SUM(CASE WHEN progress_completed = 0 THEN 1 ELSE 0 END) = 0
      ),
      candidate_books AS (
        SELECT
          book_id,
          series_id,
          meta_number_sort,
          id
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
          AND progress_completed IS NULL
          AND series_id IN (SELECT series_id FROM on_deck_series)
      )
      SELECT candidate.book_id
      FROM candidate_books candidate
      JOIN on_deck_series series ON series.series_id = candidate.series_id
      WHERE NOT EXISTS (
        SELECT 1
        FROM candidate_books earlier
        WHERE earlier.series_id = candidate.series_id
          AND (
            earlier.meta_number_sort < candidate.meta_number_sort
            OR (
              earlier.meta_number_sort = candidate.meta_number_sort
              AND earlier.id < candidate.id
            )
          )
      )
      ORDER BY series.most_recent_read_date DESC, candidate.id ASC
      LIMIT ? OFFSET ?
      """
    arguments += StatementArguments([instanceId])
    arguments += StatementArguments([limit, max(0, offset)])

    return try String.fetchAll(db, sql: sql, arguments: arguments)
  }

  private func recentlyReleasedCutoffDateString(referenceDate: Date = Date()) -> String {
    let cutoffDate = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: cutoffDate)
  }

  /// `downloadedOnly` restricts the candidates to downloaded books (offline
  /// mode); otherwise the whole local projection of the series takes part.
  func fetchContinueReadingBook(seriesId: String, instanceId: String, downloadedOnly: Bool) -> Book? {
    guard !seriesId.isEmpty, !instanceId.isEmpty else { return nil }
    return try? read { db in
      if let inProgress = try fetchLatestSeriesBook(
        db: db,
        seriesId: seriesId,
        instanceId: instanceId,
        completed: false,
        downloadedOnly: downloadedOnly
      ) {
        return inProgress.toBook()
      }

      let orderedBooks = try fetchSeriesBooksForContinueReading(
        db: db, seriesId: seriesId, instanceId: instanceId, downloadedOnly: downloadedOnly)
      guard !orderedBooks.isEmpty else { return nil }

      if let lastRead = try fetchLatestSeriesBook(
        db: db,
        seriesId: seriesId,
        instanceId: instanceId,
        completed: true,
        downloadedOnly: downloadedOnly
      ),
        let lastReadIndex = orderedBooks.firstIndex(where: { $0.id == lastRead.id }),
        let nextBook = orderedBooks.nextToRead(
          after: lastReadIndex, isRead: { $0.progressCompleted == true })
      {
        return nextBook.toBook()
      }

      if let firstUnread = orderedBooks.first(where: {
        Self.readStatus(completed: $0.progressCompleted, readDate: $0.progressReadDate) == .unread
      }) {
        return firstUnread.toBook()
      }

      return orderedBooks.first?.toBook()
    }
  }

  func upsertBook(dto: Book, instanceId: String) {
    do {
      try write { db in
        let compositeId = CompositeID.generate(instanceId: instanceId, id: dto.id)
        if var existing = try KomgaBook.fetchOne(db, key: compositeId) {
          applyBook(dto: dto, to: &existing)
          try save(existing, db: db)
        } else {
          let newBook = KomgaBook(
            id: compositeId,
            bookId: dto.id,
            seriesId: dto.seriesId,
            libraryId: dto.libraryId,
            instanceId: instanceId,
            name: dto.name,
            url: dto.url,
            number: dto.number,
            created: dto.created,
            lastModified: dto.lastModified,
            sizeBytes: dto.sizeBytes,
            size: dto.size,
            media: dto.media,
            metadata: dto.metadata,
            readProgress: dto.readProgress,
            isUnavailable: dto.deleted,
            oneshot: dto.oneshot,
            seriesTitle: dto.seriesTitle
          )
          try save(newBook, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert book: \(error)")
    }
  }

  func deleteBook(id: String, instanceId: String) {
    do {
      _ = try write { db in
        try KomgaBook.deleteOne(db, key: CompositeID.generate(instanceId: instanceId, id: id))
      }
    } catch {
      logger.error("Failed to delete book: \(error)")
    }
  }

  @discardableResult
  func markBookUnavailable(bookId: String, instanceId: String) -> Bool {
    do {
      return try write { db in
        guard var book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else {
          return false
        }
        guard !book.isUnavailable else { return true }
        book.isUnavailable = true
        try save(book, db: db)
        return true
      }
    } catch {
      logger.error("Failed to mark book unavailable: \(error)")
      return false
    }
  }

  func markSeriesBooksUnavailable(seriesId: String, instanceId: String) -> [String] {
    do {
      return try write { db in
        let books = try fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)
        var changedBookIds: [String] = []
        for var book in books {
          if !book.isUnavailable {
            book.isUnavailable = true
            try save(book, db: db)
          }
          changedBookIds.append(book.bookId)
        }
        return changedBookIds
      }
    } catch {
      logger.error("Failed to mark series books unavailable: \(error)")
      return []
    }
  }

  func fetchAllSeriesBookIds(seriesId: String, instanceId: String) -> [String] {
    guard !seriesId.isEmpty, !instanceId.isEmpty else { return [] }
    return
      (try? read { db in
        try String.fetchAll(
          db,
          sql: """
            SELECT book_id
            FROM \(KomgaBook.databaseTableName)
            WHERE instance_id = ? AND series_id = ?
            ORDER BY meta_number_sort, id
            """,
          arguments: [instanceId, seriesId]
        )
      }) ?? []
  }

  func upsertBooks(_ books: [Book], instanceId: String) {
    do {
      try write { db in
        let existingBooks = try fetchBooksByIds(db: db, ids: books.map(\.id), instanceId: instanceId)
        let existingById = Dictionary(uniqueKeysWithValues: existingBooks.map { ($0.bookId, $0) })

        for book in books {
          var record =
            existingById[book.id]
            ?? KomgaBook(
              id: CompositeID.generate(instanceId: instanceId, id: book.id),
              bookId: book.id,
              seriesId: book.seriesId,
              libraryId: book.libraryId,
              instanceId: instanceId,
              name: book.name,
              url: book.url,
              number: book.number,
              created: book.created,
              lastModified: book.lastModified,
              sizeBytes: book.sizeBytes,
              size: book.size,
              media: book.media,
              metadata: book.metadata,
              readProgress: book.readProgress,
              isUnavailable: book.deleted,
              oneshot: book.oneshot,
              seriesTitle: book.seriesTitle
            )
          applyBook(dto: book, to: &record)
          try save(record, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert books: \(error)")
    }
  }

  func upsertReadingProgressBooks(
    _ books: [Book],
    instanceId: String,
    replaceExisting: Bool = true
  ) {
    do {
      try write { db in
        for book in books {
          let compositeId = CompositeID.generate(instanceId: instanceId, id: book.id)
          if var existing = try KomgaBook.fetchOne(db, key: compositeId) {
            let oldSeriesId = existing.seriesId
            let oldStatus = readingStatus(
              progressCompleted: existing.progressCompleted,
              progressPage: existing.progressPage
            )
            existing.updateReadProgress(book.readProgress)
            if existing.seriesId != book.seriesId { existing.seriesId = book.seriesId }
            if existing.libraryId != book.libraryId { existing.libraryId = book.libraryId }
            if existing.seriesTitle != book.seriesTitle { existing.seriesTitle = book.seriesTitle }
            try save(existing, db: db)
            let newStatus = readingStatus(
              progressCompleted: existing.progressCompleted,
              progressPage: existing.progressPage
            )
            if oldSeriesId == existing.seriesId {
              updateSeriesReadingCounts(
                db: db,
                seriesId: existing.seriesId,
                instanceId: instanceId,
                oldStatus: oldStatus,
                newStatus: newStatus
              )
            } else {
              updateSeriesReadingCounts(
                db: db,
                seriesId: oldSeriesId,
                instanceId: instanceId,
                oldStatus: oldStatus,
                newStatus: -1
              )
              updateSeriesReadingCounts(
                db: db,
                seriesId: existing.seriesId,
                instanceId: instanceId,
                oldStatus: -1,
                newStatus: newStatus
              )
            }
          } else if replaceExisting {
            let newBook = KomgaBook(
              id: compositeId,
              bookId: book.id,
              seriesId: book.seriesId,
              libraryId: book.libraryId,
              instanceId: instanceId,
              name: book.name,
              url: book.url,
              number: book.number,
              created: book.created,
              lastModified: book.lastModified,
              sizeBytes: book.sizeBytes,
              size: book.size,
              media: book.media,
              metadata: book.metadata,
              readProgress: book.readProgress,
              isUnavailable: book.deleted,
              oneshot: book.oneshot,
              seriesTitle: book.seriesTitle
            )
            try save(newBook, db: db)
          }
        }
      }
    } catch {
      logger.error("Failed to upsert reading progress books: \(error)")
    }
  }

  func deleteBooksNotIn(_ bookIds: Set<String>, instanceId: String) -> Int {
    (try? write { db in
      var deletedCount = 0
      var lastScannedId: String?

      while true {
        var request =
          KomgaBook
          .filter(KomgaBook.Columns.instanceId == instanceId)
          .order(KomgaBook.Columns.id)
          .limit(Self.recordFetchChunkSize)

        if let lastScannedId {
          request = request.filter(KomgaBook.Columns.id > lastScannedId)
        }

        let batch = try request.fetchAll(db)
        guard !batch.isEmpty else { break }
        lastScannedId = batch.last?.id

        for book in batch where !bookIds.contains(book.bookId) {
          try KomgaBook.deleteOne(db, key: book.id)
          deletedCount += 1
        }
      }

      return deletedCount
    }) ?? 0
  }

  func fetchBook(id: String) async -> Book? {
    try? read { db in
      try fetchBookRecord(db: db, id: id)?.toBook()
    }
  }

  /// The book to read after `bookId` in its series, or in `readListId`'s
  /// order: the first later book that isn't read, else the plain next book.
  func getNextBook(instanceId: String, bookId: String, readListId: String?) async -> Book? {
    try? read { db in
      guard let currentBook = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else {
        return nil
      }
      let books: [Book]
      if let readListId {
        books = try fetchReadListBooks(db: db, readListId: readListId, instanceId: instanceId, page: 0, size: 1000)
      } else {
        books = try fetchSeriesBooks(
          db: db, seriesId: currentBook.seriesId, instanceId: instanceId, page: 0, size: 1000)
      }
      guard let currentIndex = books.firstIndex(where: { $0.id == bookId }) else {
        return nil
      }
      return books.nextToRead(after: currentIndex, isRead: { $0.isCompleted })
    }
  }

  func getPreviousBook(instanceId: String, bookId: String, readListId: String? = nil) async -> Book? {
    try? read { db in
      guard let currentBook = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else {
        return nil
      }
      let books: [Book]
      if let readListId {
        books = try fetchReadListBooks(db: db, readListId: readListId, instanceId: instanceId, page: 0, size: 1000)
      } else {
        books = try fetchSeriesBooks(
          db: db, seriesId: currentBook.seriesId, instanceId: instanceId, page: 0, size: 1000)
      }
      guard let currentIndex = books.firstIndex(where: { $0.id == bookId }), currentIndex > 0 else {
        return nil
      }
      return books[currentIndex - 1]
    }
  }

  func fetchPages(id: String) -> [BookPage]? {
    fetchPages(id: id, instanceId: AppConfig.current.instanceId)
  }

  func fetchPages(id: String, instanceId: String) -> [BookPage]? {
    try? read { db in
      try fetchBookRecord(db: db, id: id, instanceId: instanceId)?.pages
    }
  }

  func fetchIsolatePages(id: String) -> [Int]? {
    try? read { db in
      try fetchBookRecord(db: db, id: id)?.isolatePages
    }
  }

  func updateIsolatePages(bookId: String, pages: [Int]) {
    updateBookRecord(bookId: bookId) { book in
      book.isolatePages = pages
    }
  }

  func fetchBookEpubThemePreferences(bookId: String) -> EpubThemePreferences? {
    try? read { db in
      guard let raw = try fetchBookRecord(db: db, id: bookId)?.epubPreferencesRaw else {
        return nil
      }
      return EpubThemePreferences(rawValue: raw)
    }
  }

  func updateBookEpubThemePreferences(bookId: String, preferences: EpubThemePreferences?) {
    updateBookRecord(bookId: bookId) { book in
      book.epubPreferencesRaw = preferences?.rawValue
    }
  }

  func fetchBookEpubProgression(bookId: String) async -> R2Progression? {
    let raw = try? read { db in
      try fetchBookRecord(db: db, id: bookId)?.epubProgressionRaw
    }
    switch await decodeStoredEpubProgressionState(raw ?? nil) {
    case .available(let progression):
      return progression
    case .missing, .unknown:
      return nil
    }
  }

  func updateBookEpubProgression(bookId: String, progression: R2Progression?) async {
    let raw = await encodeEpubProgressionRecord(progression: progression)
    updateBookRecord(bookId: bookId) { book in
      book.epubProgressionRaw = raw
    }
  }

  func fetchTOC(id: String) -> [ReaderTOCEntry]? {
    fetchTOC(id: id, instanceId: AppConfig.current.instanceId)
  }

  func fetchTOC(id: String, instanceId: String) -> [ReaderTOCEntry]? {
    try? read { db in
      try fetchBookRecord(db: db, id: id, instanceId: instanceId)?.tableOfContents
    }
  }

  func updateBookPages(bookId: String, pages: [BookPage]) {
    updateBookPages(bookId: bookId, instanceId: AppConfig.current.instanceId, pages: pages)
  }

  func updateBookPages(bookId: String, instanceId: String, pages: [BookPage]) {
    updateBookRecord(bookId: bookId, instanceId: instanceId) { book in
      book.pages = pages
    }
  }

  func updateBookTOC(bookId: String, toc: [ReaderTOCEntry]) {
    updateBookTOC(bookId: bookId, instanceId: AppConfig.current.instanceId, toc: toc)
  }

  func updateBookTOC(bookId: String, instanceId: String, toc: [ReaderTOCEntry]) {
    updateBookRecord(bookId: bookId, instanceId: instanceId) { book in
      book.tableOfContents = toc
    }
  }

  func updateBookWebPubManifest(bookId: String, manifest: WebPubPublication) async {
    let data = RawCodableStore.encode(manifest)
    updateBookRecord(bookId: bookId) { book in
      book.webPubManifestRaw = data
    }
  }

  func fetchWebPubManifest(bookId: String) async -> WebPubPublication? {
    await fetchWebPubManifest(bookId: bookId, instanceId: AppConfig.current.instanceId)
  }

  func fetchWebPubManifest(bookId: String, instanceId: String) async -> WebPubPublication? {
    try? read { db in
      let data = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId)?.webPubManifestRaw
      return RawCodableStore.decode(WebPubPublication.self, from: data)
    }
  }
}

extension DatabaseOperator {
  func fetchBooksByIds(db: Database, ids: [String], instanceId: String) throws -> [KomgaBook] {
    guard !ids.isEmpty else { return [] }
    let uniqueCompositeIds = Array(Set(ids.map { CompositeID.generate(instanceId: instanceId, id: $0) }))
    var books: [KomgaBook] = []

    for start in stride(from: 0, to: uniqueCompositeIds.count, by: Self.recordFetchChunkSize) {
      let end = min(start + Self.recordFetchChunkSize, uniqueCompositeIds.count)
      let chunk = Array(uniqueCompositeIds[start..<end])
      let fetched = try KomgaBook.fetchAll(db, keys: chunk)
      books.append(contentsOf: fetched)
    }

    return Self.orderedByIds(books, ids: ids, id: \.bookId)
  }

  func fetchSeriesBooks(
    db: Database,
    seriesId: String,
    instanceId: String,
    page: Int,
    size: Int,
    browseOpts: BookBrowseOptions = BookBrowseOptions()
  ) throws -> [Book] {
    let books = try fetchBooks(db: db, instanceId: instanceId, seriesId: seriesId)
    return Self.paginate(
      Self.filteredBrowseBooks(books, libraryIds: nil, searchText: "", browseOpts: browseOpts),
      offset: page * size,
      limit: size
    ).map { $0.toBook() }
  }

  func fetchReadListBooks(
    db: Database,
    readListId: String,
    instanceId: String,
    page: Int,
    size: Int,
    browseOpts: ReadListBookBrowseOptions = ReadListBookBrowseOptions()
  ) throws -> [Book] {
    guard let readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
      return []
    }
    let books = try fetchBooksByIds(db: db, ids: readList.bookIds, instanceId: instanceId)
      .filter { Self.matchesBook($0, readListBrowseOpts: browseOpts) }
    return Self.paginate(books, offset: page * size, limit: size).map { $0.toBook() }
  }

  func updateBookRecord(bookId: String, update: (inout KomgaBook) -> Void) {
    updateBookRecord(bookId: bookId, instanceId: AppConfig.current.instanceId, update: update)
  }

  func updateBookRecord(bookId: String, instanceId: String, update: (inout KomgaBook) -> Void) {
    guard !instanceId.isEmpty else { return }
    do {
      try write { db in
        guard var book = try fetchBookRecord(db: db, id: bookId, instanceId: instanceId) else { return }
        update(&book)
        try save(book, db: db)
      }
    } catch {
      logger.error("Failed to update book: \(error)")
    }
  }

  func applyBook(dto: Book, to existing: inout KomgaBook) {
    let mediaRaw = RawCodableStore.encode(dto.media)
    let metadataRaw = RawCodableStore.encode(dto.metadata)
    let readProgressRaw = RawCodableStore.encodeOptional(dto.readProgress)

    if existing.name != dto.name { existing.name = dto.name }
    if existing.url != dto.url { existing.url = dto.url }
    if existing.number != dto.number { existing.number = dto.number }
    if existing.lastModified != dto.lastModified { existing.lastModified = dto.lastModified }
    if existing.sizeBytes != dto.sizeBytes { existing.sizeBytes = dto.sizeBytes }
    if existing.size != dto.size { existing.size = dto.size }
    if mediaRaw == nil || existing.mediaRaw != mediaRaw {
      existing.updateMedia(dto.media, raw: mediaRaw)
    }
    if metadataRaw == nil || existing.metadataRaw != metadataRaw {
      existing.updateMetadata(dto.metadata, raw: metadataRaw)
    }
    if existing.readProgressRaw != readProgressRaw {
      existing.updateReadProgress(dto.readProgress, raw: readProgressRaw)
    }
    if existing.isUnavailable != dto.deleted { existing.isUnavailable = dto.deleted }
    if existing.oneshot != dto.oneshot { existing.oneshot = dto.oneshot }
    if existing.seriesTitle != dto.seriesTitle { existing.seriesTitle = dto.seriesTitle }
  }

  func fetchLatestSeriesBook(
    db: Database,
    seriesId: String,
    instanceId: String,
    completed: Bool,
    downloadedOnly: Bool
  ) throws -> KomgaBook? {
    try fetchSeriesBooksForContinueReading(
      db: db, seriesId: seriesId, instanceId: instanceId, downloadedOnly: downloadedOnly
    )
    .filter { $0.progressCompleted == completed && $0.progressReadDate != nil }
    .sorted { ($0.progressReadDate ?? .distantPast) > ($1.progressReadDate ?? .distantPast) }
    .first
  }

  func fetchSeriesBooksForContinueReading(
    db: Database,
    seriesId: String,
    instanceId: String,
    downloadedOnly: Bool
  ) throws -> [KomgaBook] {
    let base = KomgaBook.filter(
      KomgaBook.Columns.instanceId == instanceId
        && KomgaBook.Columns.seriesId == seriesId
    )
    let scoped =
      downloadedOnly
      ? base.filter(KomgaBook.Columns.downloadStatusRaw == "downloaded")
      : base
    return
      try scoped
      .order(KomgaBook.Columns.metaNumberSort, KomgaBook.Columns.id)
      .fetchAll(db)
  }

  func updateSeriesReadingCounts(
    db: Database,
    seriesId: String,
    instanceId: String,
    oldStatus: Int,
    newStatus: Int
  ) {
    guard var series = try? fetchSeriesRecord(db: db, id: seriesId, instanceId: instanceId) else { return }

    var unread = series.booksUnreadCount
    var inProgress = series.booksInProgressCount
    var read = series.booksReadCount

    switch oldStatus {
    case 0: unread -= 1
    case 1: inProgress -= 1
    case 2: read -= 1
    default: break
    }

    switch newStatus {
    case 0: unread += 1
    case 1: inProgress += 1
    case 2: read += 1
    default: break
    }

    if unread < 0 || inProgress < 0 || read < 0 || (unread + inProgress + read) > series.booksCount {
      syncSeriesReadingStatus(db: db, seriesId: seriesId, instanceId: instanceId)
      return
    }

    series.booksUnreadCount = max(0, unread)
    series.booksInProgressCount = max(0, inProgress)
    series.booksReadCount = max(0, read)
    try? save(series, db: db)
  }

  private func makeBookDisplayItem(
    db: Database,
    book: KomgaBook,
    includeOfflineProtection: Bool
  ) throws -> BookDisplayItem {
    if includeOfflineProtection {
      let sourcesByBookId = try fetchOfflineProtectionSources(
        db: db,
        instanceId: book.instanceId,
        targetBooks: [book]
      )
      return Self.makeBookDisplayItem(
        book,
        protectionSources: sourcesByBookId[book.bookId] ?? []
      )
    }
    return Self.makeBookDisplayItem(book)
  }

  private func fetchOfflineProtectionSources(
    db: Database,
    instanceId: String,
    targetBooks: [KomgaBook]
  ) throws -> [String: [OfflineProtectionSource]] {
    guard !targetBooks.isEmpty else { return [:] }
    let targetBookIds = targetBooks.map(\.bookId)
    let seriesIds = Array(Set(targetBooks.map(\.seriesId)))
    var sourceBooksById: [String: KomgaBook] = [:]
    for sourceBook in try fetchBooks(db: db, instanceId: instanceId, seriesIds: seriesIds) {
      sourceBooksById[sourceBook.bookId] = sourceBook
    }
    for book in targetBooks {
      sourceBooksById[book.bookId] = book
    }

    let readListSources = try fetchReadListsAndMembershipsContainingBooks(
      db: db,
      instanceId: instanceId,
      bookIds: targetBookIds
    )
    let readListBookIds = Set(readListSources.memberships.map(\.bookId))
    let missingBookIds = readListBookIds.filter { sourceBooksById[$0] == nil }
    for sourceBook in try fetchBooksByIds(db: db, ids: Array(missingBookIds), instanceId: instanceId) {
      sourceBooksById[sourceBook.bookId] = sourceBook
    }

    let protectionIndex = OfflineProtectionIndex(
      books: Array(sourceBooksById.values),
      series: try fetchSeriesByIds(db: db, ids: seriesIds, instanceId: instanceId),
      readLists: readListSources.readLists,
      readListMemberships: readListSources.memberships
    )
    return Dictionary(
      uniqueKeysWithValues: targetBooks.map { book in
        (book.bookId, protectionIndex.sources(for: book))
      })
  }

  nonisolated static func makeBookDisplayItem(
    _ book: KomgaBook,
    protectionSources: [OfflineProtectionSource] = []
  ) -> BookDisplayItem {
    BookDisplayItem(
      instanceId: book.instanceId,
      book: book.toBook(),
      downloadStatus: book.downloadStatus,
      readListIds: book.readListIds,
      protectionSources: protectionSources
    )
  }

  nonisolated static func filteredBrowseBooks(
    _ books: [KomgaBook],
    libraryIds: [String]?,
    searchText: String,
    browseOpts: BookBrowseOptions,
    offlineOnly: Bool = false
  ) -> [KomgaBook] {
    let libraryIds = libraryIds ?? []
    return sortBooks(
      books.filter { book in
        if !libraryIds.isEmpty && !libraryIds.contains(book.libraryId) { return false }
        if !searchText.isEmpty
          && !book.name.localizedStandardContains(searchText)
          && !book.metaTitle.localizedStandardContains(searchText)
        {
          return false
        }
        if offlineOnly && book.downloadStatusRaw != "downloaded" && book.downloadStatusRaw != "pending" {
          return false
        }
        return matchesBook(book, browseOpts: browseOpts)
      },
      sort: browseOpts.sortString
    )
  }

  nonisolated static func matchesBook(_ book: KomgaBook, browseOpts: BookBrowseOptions) -> Bool {
    if let deletedState = browseOpts.deletedFilter.effectiveBool, book.isUnavailable != deletedState {
      return false
    }
    if let oneshotState = browseOpts.oneshotFilter.effectiveBool, book.oneshot != oneshotState {
      return false
    }
    let status = readStatus(completed: book.progressCompleted, readDate: book.progressReadDate)
    if !browseOpts.includeReadStatuses.isEmpty && !browseOpts.includeReadStatuses.contains(status) {
      return false
    }
    if !browseOpts.excludeReadStatuses.isEmpty && browseOpts.excludeReadStatuses.contains(status) {
      return false
    }
    return matchesBookMetadataFilter(book: book, filter: browseOpts.metadataFilter)
  }

  nonisolated static func matchesBook(_ book: KomgaBook, readListBrowseOpts: ReadListBookBrowseOptions) -> Bool {
    if let deletedState = readListBrowseOpts.deletedFilter.effectiveBool, book.isUnavailable != deletedState {
      return false
    }
    if let oneshotState = readListBrowseOpts.oneshotFilter.effectiveBool, book.oneshot != oneshotState {
      return false
    }
    let status = readStatus(completed: book.progressCompleted, readDate: book.progressReadDate)
    if !readListBrowseOpts.includeReadStatuses.isEmpty && !readListBrowseOpts.includeReadStatuses.contains(status) {
      return false
    }
    if !readListBrowseOpts.excludeReadStatuses.isEmpty && readListBrowseOpts.excludeReadStatuses.contains(status) {
      return false
    }
    return matchesBookMetadataFilter(book: book, filter: readListBrowseOpts.metadataFilter)
  }

  nonisolated static func appendBookBrowseSQLFilters(
    searchText: String,
    browseOpts: BookBrowseOptions,
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
      sql += "\nAND download_status_raw IN ('downloaded', 'pending')"
    }

    if let deletedState = browseOpts.deletedFilter.effectiveBool {
      sql += "\nAND is_unavailable = ?"
      arguments += StatementArguments([deletedState])
    }

    if let oneshotState = browseOpts.oneshotFilter.effectiveBool {
      sql += "\nAND oneshot = ?"
      arguments += StatementArguments([oneshotState])
    }

    appendBookReadStatusSQLFilter(
      include: browseOpts.includeReadStatuses,
      exclude: browseOpts.excludeReadStatuses,
      sql: &sql
    )
    appendBookMetadataSQLFilter(browseOpts.metadataFilter, sql: &sql, arguments: &arguments)
  }

  nonisolated static func appendBookReadStatusSQLFilter(
    include: Set<ReadStatus>,
    exclude: Set<ReadStatus>,
    sql: inout String
  ) {
    if !include.isEmpty {
      let clauses = include.sorted { $0.rawValue < $1.rawValue }.map(bookReadStatusSQL)
      sql += "\nAND (\(clauses.joined(separator: " OR ")))"
    }

    if !exclude.isEmpty {
      let clauses = exclude.sorted { $0.rawValue < $1.rawValue }.map(bookReadStatusSQL)
      sql += "\nAND NOT (\(clauses.joined(separator: " OR ")))"
    }
  }

  nonisolated static func bookReadStatusSQL(_ status: ReadStatus) -> String {
    switch status {
    case .read:
      return "(progress_completed = 1)"
    case .inProgress:
      return "(COALESCE(progress_completed, 0) = 0 AND progress_read_date IS NOT NULL)"
    case .unread:
      return "(COALESCE(progress_completed, 0) = 0 AND progress_read_date IS NULL)"
    }
  }

  nonisolated static func appendBookMetadataSQLFilter(
    _ filter: MetadataFilterConfig,
    sql: inout String,
    arguments: inout StatementArguments
  ) {
    appendMetadataIndexSQLFilter(
      column: "meta_authors_index",
      values: filter.authors,
      logic: filter.authorsLogic,
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
  }

  nonisolated static func appendMetadataIndexSQLFilter(
    column: String,
    values: [String]?,
    logic: FilterLogic,
    sql: inout String,
    arguments: inout StatementArguments
  ) {
    let patterns = (values ?? []).compactMap(sqlMetadataIndexPattern)
    guard !patterns.isEmpty else { return }

    switch logic {
    case .all:
      for pattern in patterns {
        sql += "\nAND \(column) LIKE ? ESCAPE char(92)"
        arguments += StatementArguments([pattern])
      }
    case .any:
      let clauses = Array(repeating: "\(column) LIKE ? ESCAPE char(92)", count: patterns.count)
      sql += "\nAND (\(clauses.joined(separator: " OR ")))"
      arguments += StatementArguments(patterns)
    }
  }

  nonisolated static func bookBrowseOrderSQL(sort: String) -> String {
    let direction = sort.contains("desc") ? "DESC" : "ASC"
    if sort.contains("series") && sort.contains("metadata.numberSort") {
      return
        "COALESCE(NULLIF(series_title, ''), series_id) \(direction), meta_number_sort \(direction), id ASC"
    }
    if sort.contains("createdDate") {
      return "created \(direction), id ASC"
    }
    if sort.contains("lastModifiedDate") {
      return "last_modified \(direction), id ASC"
    }
    if sort.contains("metadata.releaseDate") {
      return "COALESCE(meta_release_date, '') \(direction), id ASC"
    }
    if sort.contains("readProgress.readDate") {
      return "progress_read_date \(direction), id ASC"
    }
    if sort.contains("downloadAt") {
      return "download_at \(direction), id ASC"
    }
    if sort.contains("fileSize") {
      return "size_bytes \(direction), id ASC"
    }
    if sort.contains("name") {
      return "name \(direction), id ASC"
    }
    if sort.contains("media.pagesCount") {
      return "media_pages_count \(direction), id ASC"
    }
    return "meta_title \(direction), id ASC"
  }

  nonisolated static func sortBooks(_ books: [KomgaBook], sort: String) -> [KomgaBook] {
    let isAsc = !sort.contains("desc")
    if sort.contains("created") {
      return books.sorted { isAsc ? $0.created < $1.created : $0.created > $1.created }
    }
    if sort.contains("metadata.releaseDate") {
      return books.sorted {
        isAsc
          ? ($0.metaReleaseDate ?? "") < ($1.metaReleaseDate ?? "")
          : ($0.metaReleaseDate ?? "") > ($1.metaReleaseDate ?? "")
      }
    }
    if sort.contains("readProgress.readDate") {
      return books.sorted {
        isAsc
          ? ($0.progressReadDate ?? .distantPast) < ($1.progressReadDate ?? .distantPast)
          : ($0.progressReadDate ?? .distantPast) > ($1.progressReadDate ?? .distantPast)
      }
    }
    if sort.contains("downloadAt") {
      return books.sorted {
        isAsc
          ? ($0.downloadAt ?? .distantPast) < ($1.downloadAt ?? .distantPast)
          : ($0.downloadAt ?? .distantPast) > ($1.downloadAt ?? .distantPast)
      }
    }
    if sort.contains("series") && sort.contains("metadata.numberSort") {
      return books.sorted {
        let lhsSeries = $0.seriesTitle.isEmpty ? $0.seriesId : $0.seriesTitle
        let rhsSeries = $1.seriesTitle.isEmpty ? $1.seriesId : $1.seriesTitle
        if lhsSeries != rhsSeries {
          return isAsc ? lhsSeries < rhsSeries : lhsSeries > rhsSeries
        }
        if $0.metaNumberSort != $1.metaNumberSort {
          return isAsc ? $0.metaNumberSort < $1.metaNumberSort : $0.metaNumberSort > $1.metaNumberSort
        }
        return $0.id < $1.id
      }
    }
    if sort.contains("metadata.numberSort") {
      return books.sorted {
        if $0.metaNumberSort != $1.metaNumberSort {
          return isAsc ? $0.metaNumberSort < $1.metaNumberSort : $0.metaNumberSort > $1.metaNumberSort
        }
        return $0.id < $1.id
      }
    }
    return books.sorted { isAsc ? $0.name < $1.name : $0.name > $1.name }
  }

  private func encodeEpubProgressionRecord(progression: R2Progression?) async -> Data? {
    await MainActor.run {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let record =
        if let progression {
          EpubProgressionRecord(state: .available, progression: progression)
        } else {
          EpubProgressionRecord(state: .missing, progression: nil)
        }
      return try? encoder.encode(record)
    }
  }

  func decodeStoredEpubProgressionState(_ raw: Data?) async -> StoredEpubProgressionState {
    guard let raw else {
      return .unknown
    }

    if raw.isEmpty {
      return .missing
    }

    return await MainActor.run {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601

      if let record = try? decoder.decode(EpubProgressionRecord.self, from: raw) {
        switch record.state {
        case .available:
          if let progression = record.progression {
            return .available(progression)
          }
          return .unknown
        case .missing:
          return .missing
        }
      }

      if let progression = try? decoder.decode(R2Progression.self, from: raw) {
        let locator = progression.locator
        let isEmptyLocator =
          locator.href.isEmpty
          && locator.type.isEmpty
          && locator.title == nil
          && locator.locations == nil
          && locator.text == nil
          && locator.koboSpan == nil
        return isEmptyLocator ? .missing : .available(progression)
      }

      if let jsonObject = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
        let locator = jsonObject["locator"] as? [String: Any], locator.isEmpty
      {
        return .missing
      }

      return .unknown
    }
  }
}
