//
// DatabaseOperator.swift
//
//

import Foundation
import GRDB
import OSLog

struct InstanceSummary: Sendable {
  let id: UUID
  let displayName: String
  let protected: Bool
}

struct PendingProgressSummary: Sendable {
  let id: String
  let instanceId: String
  let bookId: String
  let page: Int
  let completed: Bool
  let createdAt: Date
  let progressionData: Data?
}

struct DownloadQueueSummary: Sendable {
  let downloadingCount: Int
  let pendingCount: Int
  let failedCount: Int

  nonisolated static let empty = DownloadQueueSummary(
    downloadingCount: 0,
    pendingCount: 0,
    failedCount: 0
  )

  var isEmpty: Bool {
    return downloadingCount == 0 && pendingCount == 0 && failedCount == 0
  }
}

nonisolated struct HistoricalEventLocalReferences: Equatable, Sendable {
  let bookNameById: [String: String]
  let seriesNameById: [String: String]

  static let empty = HistoricalEventLocalReferences(bookNameById: [:], seriesNameById: [:])

  var hasMatches: Bool {
    !bookNameById.isEmpty || !seriesNameById.isEmpty
  }
}

actor DatabaseOperator {
  private actor SharedStore {
    private var sharedDatabase: DatabaseOperator?

    func configure(databaseQueue: DatabaseQueue) {
      sharedDatabase = DatabaseOperator(databaseQueue: databaseQueue)
    }

    func database() throws -> DatabaseOperator {
      guard let sharedDatabase else {
        throw AppErrorType.storageNotConfigured(message: "DatabaseOperator has not been configured")
      }
      return sharedDatabase
    }

    func databaseIfConfigured() -> DatabaseOperator? {
      sharedDatabase
    }
  }

  private static let sharedStore = SharedStore()
  nonisolated static let recordFetchChunkSize = 900

  let dbQueue: DatabaseQueue
  let logger = AppLogger(.database)

  init(databaseQueue: DatabaseQueue) {
    self.dbQueue = databaseQueue
  }

  static func configure(databaseQueue: DatabaseQueue) async {
    await sharedStore.configure(databaseQueue: databaseQueue)
  }

  static func database() async throws -> DatabaseOperator {
    try await sharedStore.database()
  }

  static func databaseIfConfigured() async -> DatabaseOperator? {
    await sharedStore.databaseIfConfigured()
  }

  func read<T>(_ body: (Database) throws -> T) throws -> T {
    try dbQueue.read(body)
  }

  func write<T>(_ body: (Database) throws -> T) throws -> T {
    try dbQueue.write(body)
  }

  func save(_ record: KomgaInstance, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: KomgaLibrary, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: KomgaSeries, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: KomgaBook, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: KomgaCollection, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: KomgaReadList, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: CustomFont, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: PendingProgress, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: SavedFilter, db: Database) throws {
    var record = record
    try record.save(db)
  }

  func save(_ record: EpubThemePreset, db: Database) throws {
    var record = record
    try record.save(db)
  }
}

extension DatabaseOperator {
  func fetchBookRecord(db: Database, id: String, instanceId: String? = nil) throws -> KomgaBook? {
    let compositeId = instanceId.map { CompositeID.generate(instanceId: $0, id: id) } ?? CompositeID.generate(id: id)
    return try KomgaBook.fetchOne(db, key: compositeId)
  }

  func fetchSeriesRecord(db: Database, id: String, instanceId: String? = nil) throws -> KomgaSeries? {
    let compositeId = instanceId.map { CompositeID.generate(instanceId: $0, id: id) } ?? CompositeID.generate(id: id)
    return try KomgaSeries.fetchOne(db, key: compositeId)
  }

  func fetchCollectionRecord(db: Database, id: String, instanceId: String? = nil) throws -> KomgaCollection? {
    let compositeId = instanceId.map { CompositeID.generate(instanceId: $0, id: id) } ?? CompositeID.generate(id: id)
    return try KomgaCollection.fetchOne(db, key: compositeId)
  }

  func fetchReadListRecord(db: Database, id: String, instanceId: String? = nil) throws -> KomgaReadList? {
    let compositeId = instanceId.map { CompositeID.generate(instanceId: $0, id: id) } ?? CompositeID.generate(id: id)
    return try KomgaReadList.fetchOne(db, key: compositeId)
  }

  func fetchBooks(db: Database, instanceId: String) throws -> [KomgaBook] {
    try KomgaBook
      .filter(KomgaBook.Columns.instanceId == instanceId)
      .fetchAll(db)
  }

  func fetchBooks(db: Database, instanceId: String, seriesId: String) throws -> [KomgaBook] {
    try KomgaBook
      .filter(KomgaBook.Columns.instanceId == instanceId && KomgaBook.Columns.seriesId == seriesId)
      .fetchAll(db)
  }

  func fetchBooks(db: Database, instanceId: String, seriesIds: [String]) throws -> [KomgaBook] {
    guard !seriesIds.isEmpty else { return [] }
    var books: [KomgaBook] = []
    for seriesIds in Self.chunkedSQLValues(seriesIds, chunkSize: Self.recordFetchChunkSize) {
      var sql = """
        SELECT *
        FROM \(KomgaBook.databaseTableName)
        WHERE instance_id = ?
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "series_id", values: seriesIds, sql: &sql, arguments: &arguments)
      books.append(contentsOf: try KomgaBook.fetchAll(db, sql: sql, arguments: arguments))
    }
    return books
  }

  func fetchSeriesRecords(db: Database, instanceId: String) throws -> [KomgaSeries] {
    try KomgaSeries
      .filter(KomgaSeries.Columns.instanceId == instanceId)
      .fetchAll(db)
  }

  func fetchCollections(db: Database, instanceId: String) throws -> [KomgaCollection] {
    try KomgaCollection
      .filter(KomgaCollection.Columns.instanceId == instanceId)
      .fetchAll(db)
  }

  func fetchReadLists(db: Database, instanceId: String) throws -> [KomgaReadList] {
    try KomgaReadList
      .filter(KomgaReadList.Columns.instanceId == instanceId)
      .fetchAll(db)
  }

  nonisolated static func paginate<T>(_ values: [T], offset: Int, limit: Int) -> [T] {
    guard !values.isEmpty, limit > 0 else { return [] }
    let safeOffset = min(max(0, offset), values.count)
    let end = min(safeOffset + limit, values.count)
    return Array(values[safeOffset..<end])
  }

  nonisolated static func orderedByIds<T>(
    _ values: [T],
    ids: [String],
    id: (T) -> String
  ) -> [T] {
    let idToIndex = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
    return values.sorted {
      (idToIndex[id($0)] ?? Int.max) < (idToIndex[id($1)] ?? Int.max)
    }
  }

  nonisolated static func appendSQLInFilter(
    column: String,
    values: [String],
    sql: inout String,
    arguments: inout StatementArguments
  ) {
    guard !values.isEmpty else { return }
    let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
    sql += "\nAND \(column) IN (\(placeholders))"
    arguments += StatementArguments(values)
  }

  nonisolated static func sqlContainsPattern(_ value: String) -> String {
    "%\(escapedSQLLike(value))%"
  }

  nonisolated static func sqlMetadataIndexPattern(_ value: String) -> String? {
    guard let normalized = MetadataIndex.normalize(value) else { return nil }
    return "%|\(escapedSQLLike(normalized))|%"
  }

  nonisolated static func escapedSQLLike(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }

  nonisolated static func decodeJSONStringArray(_ data: Data?) -> [String] {
    data.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
  }

  nonisolated static func readStatus(completed: Bool?, readDate: Date?) -> ReadStatus {
    if completed == true {
      return .read
    }
    if readDate != nil {
      return .inProgress
    }
    return .unread
  }

  nonisolated func readingStatus(progressCompleted: Bool?, progressPage: Int?) -> Int {
    if progressCompleted == true {
      return 2
    }
    if (progressPage ?? 0) > 0 {
      return 1
    }
    return 0
  }

  nonisolated static func matchesBookMetadataFilter(
    book: KomgaBook,
    filter: MetadataFilterConfig
  ) -> Bool {
    if !MetadataIndex.matches(
      index: book.metaAuthorsIndex,
      values: filter.authors,
      logic: filter.authorsLogic
    ) {
      return false
    }

    if !MetadataIndex.matches(
      index: book.metaTagsIndex,
      values: filter.tags,
      logic: filter.tagsLogic
    ) {
      return false
    }

    if !(book.metadata?.notableEntities ?? []).matches(
      filter.notableEntities,
      logic: filter.notableEntitiesLogic
    ) {
      return false
    }

    return true
  }

  nonisolated static func matchesSeriesMetadataFilter(
    series: KomgaSeries,
    filter: MetadataFilterConfig
  ) -> Bool {
    if !MetadataIndex.matches(
      index: series.metaPublisherIndex,
      values: filter.publishers,
      logic: filter.publishersLogic
    ) {
      return false
    }

    if !MetadataIndex.matches(
      index: series.metaAuthorsIndex,
      values: filter.authors,
      logic: filter.authorsLogic
    ) {
      return false
    }

    if !MetadataIndex.matches(
      index: series.metaGenresIndex,
      values: filter.genres,
      logic: filter.genresLogic
    ) {
      return false
    }

    if !MetadataIndex.matches(
      index: series.metaTagsIndex,
      values: filter.tags,
      logic: filter.tagsLogic
    ) {
      return false
    }

    if !(series.booksMetadata?.notableEntities ?? []).matches(
      filter.notableEntities,
      logic: filter.notableEntitiesLogic
    ) {
      return false
    }

    return true
  }
}
