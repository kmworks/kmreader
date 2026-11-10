//
// LogStore.swift
//
//

import Foundation
import GRDB
import OSLog

@globalActor
actor LogStore {
  static let shared = LogStore()

  nonisolated private static let systemLogger = Logger(
    subsystem: "com.everpcpc.kmreader",
    category: "Database"
  )
  nonisolated private static let fileName = "logs.sqlite"
  nonisolated private static let tableName = "logs"

  struct CategoryCount: Hashable, Sendable {
    let category: String
    let count: Int
  }

  struct PageCursor: Hashable, Sendable {
    let date: Date
    let id: Int64

    init(date: Date, id: Int64) {
      self.date = date
      self.id = id
    }

    init(entry: LogEntry) {
      self.init(date: entry.date, id: entry.id)
    }
  }

  private let dbQueue: DatabaseQueue?

  private init() {
    do {
      let queue = try Self.openDatabaseQueue()
      dbQueue = queue
      Task { await cleanup() }
    } catch {
      Self.logDatabaseError("Failed to prepare log database", error: error)
      dbQueue = nil
    }
  }

  nonisolated private static func openDatabaseQueue(fileManager: FileManager = .default) throws -> DatabaseQueue {
    let supportDirectory = try AppStorageDirectory.supportDirectory(fileManager: fileManager)
    let logsDir = supportDirectory.appendingPathComponent("Logs", isDirectory: true)
    try AppStorageDirectory.ensureDirectoryExists(at: logsDir, fileManager: fileManager)
    let url = logsDir.appendingPathComponent(fileName)

    let queue = try DatabaseQueue(path: url.path)
    try migrate(queue)
    return queue
  }

  nonisolated private static func migrate(_ writer: any DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = false
    #endif

    migrator.registerMigration("create_log_schema_v1") { db in
      // Legacy raw-sqlite logs are intentionally discarded during the first GRDB migration.
      if try db.tableExists(tableName) {
        try db.drop(table: tableName)
      }

      try db.create(table: tableName) { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("date", .double).notNull()
        table.column("level", .integer).notNull()
        table.column("category", .text).notNull()
        table.column("message", .text).notNull()
      }

      try db.create(index: "idx_logs_date", on: tableName, columns: ["date"])
      try db.create(index: "idx_logs_level", on: tableName, columns: ["level"])
      try db.create(index: "idx_logs_category", on: tableName, columns: ["category"])
    }

    try migrator.migrate(writer)
  }

  nonisolated private static func logDatabaseError(_ message: String, error: Error) {
    let errorMessage = String(describing: error)
    systemLogger.error("\(message, privacy: .public): \(errorMessage, privacy: .public)")
  }

  nonisolated private static func makeEntry(from row: Row) -> LogEntry {
    LogEntry(
      id: row["id"],
      date: Date(timeIntervalSince1970: row["date"]),
      level: row["level"],
      category: row["category"],
      message: row["message"]
    )
  }

  nonisolated private static func appendFilters(
    minPriority: Int?,
    category: String?,
    search: String?,
    since: Date?,
    to conditions: inout [String],
    arguments: inout StatementArguments
  ) {
    if let minPriority {
      conditions.append("level >= ?")
      arguments += [minPriority]
    }
    if let category, category != "All" {
      conditions.append("category = ?")
      arguments += [category]
    }

    let searchTerm = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !searchTerm.isEmpty {
      let keyword = "%\(searchTerm)%"
      conditions.append("(message LIKE ? OR category LIKE ?)")
      arguments += [keyword, keyword]
    }
    if let since {
      conditions.append("date >= ?")
      arguments += [since.timeIntervalSince1970]
    }
  }

  func insert(date: Date, level: Int, category: String, message: String) {
    guard let dbQueue else { return }
    do {
      try dbQueue.write { db in
        try db.execute(
          sql: "INSERT INTO \(Self.tableName) (date, level, category, message) VALUES (?, ?, ?, ?)",
          arguments: [date.timeIntervalSince1970, level, category, message]
        )
      }
    } catch {
      Self.logDatabaseError("Failed to insert log entry", error: error)
    }
  }

  struct LogEntry: Identifiable, Hashable, Sendable {
    let id: Int64
    let date: Date
    let level: Int
    let category: String
    let message: String

    func formattedLine(dateFormatter: DateFormatter) -> String {
      "[\(dateFormatter.string(from: date))] [\(LogLevel(level).rawValue)] [\(category)] \(message)"
    }
  }

  nonisolated static func makeLineDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
  }

  /// Writes every entry matching the filters to `url` as text, oldest first.
  func export(
    minPriority: Int? = nil,
    category: String? = nil,
    search: String? = nil,
    to url: URL
  ) throws {
    var conditions: [String] = []
    var arguments: StatementArguments = []
    Self.appendFilters(
      minPriority: minPriority,
      category: category,
      search: search,
      since: nil,
      to: &conditions,
      arguments: &arguments
    )
    let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
    let sql = """
      SELECT id, date, level, category, message
      FROM logs
      \(whereClause)
      ORDER BY date ASC, id ASC
      """

    try Data().write(to: url)
    guard let dbQueue else { return }

    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    let dateFormatter = Self.makeLineDateFormatter()
    let flushThreshold = 256 * 1024
    var buffer = Data()

    try dbQueue.read { db in
      let rows = try Row.fetchCursor(db, sql: sql, arguments: arguments)
      while let row = try rows.next() {
        let line = Self.makeEntry(from: row).formattedLine(dateFormatter: dateFormatter)
        buffer.append(contentsOf: line.utf8)
        buffer.append(0x0A)
        if buffer.count >= flushThreshold {
          try handle.write(contentsOf: buffer)
          buffer.removeAll(keepingCapacity: true)
        }
      }
    }
    try handle.write(contentsOf: buffer)
  }

  func query(
    minPriority: Int? = nil,
    category: String? = nil,
    search: String? = nil,
    since: Date? = nil,
    before cursor: PageCursor? = nil,
    limit: Int = 500
  ) -> [LogEntry] {
    guard let dbQueue else { return [] }

    var conditions: [String] = []
    var arguments: StatementArguments = []
    Self.appendFilters(
      minPriority: minPriority,
      category: category,
      search: search,
      since: since,
      to: &conditions,
      arguments: &arguments
    )
    if let cursor {
      conditions.append("(date < ? OR (date = ? AND id < ?))")
      arguments += [cursor.date.timeIntervalSince1970, cursor.date.timeIntervalSince1970, cursor.id]
    }

    let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
    let sql = """
      SELECT id, date, level, category, message
      FROM logs
      \(whereClause)
      ORDER BY date DESC, id DESC
      LIMIT ?
      """

    arguments += [max(1, limit)]

    do {
      return try dbQueue.read { db in
        try Row.fetchAll(db, sql: sql, arguments: arguments)
          .map(Self.makeEntry(from:))
      }
    } catch {
      Self.logDatabaseError("Failed to query log entries", error: error)
      return []
    }
  }

  func categories() -> [String] {
    guard let dbQueue else { return [] }

    do {
      return try dbQueue.read { db in
        try String.fetchAll(db, sql: "SELECT DISTINCT category FROM \(Self.tableName) ORDER BY category")
      }
    } catch {
      Self.logDatabaseError("Failed to query log categories", error: error)
      return []
    }
  }

  func categoryCounts(minPriority: Int? = nil, search: String? = nil, since: Date? = nil) -> [CategoryCount] {
    guard let dbQueue else { return [] }

    var conditions: [String] = []
    var arguments: StatementArguments = []
    Self.appendFilters(
      minPriority: minPriority,
      category: nil,
      search: search,
      since: since,
      to: &conditions,
      arguments: &arguments
    )

    let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
    let sql = """
      SELECT category, COUNT(*) as count
      FROM logs
      \(whereClause)
      GROUP BY category
      ORDER BY count DESC, category ASC
      """

    do {
      return try dbQueue.read { db in
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
          CategoryCount(category: row["category"], count: row["count"])
        }
      }
    } catch {
      Self.logDatabaseError("Failed to query log category counts", error: error)
      return []
    }
  }

  func cleanup(keepDays: Int = 7) {
    guard let dbQueue else { return }
    let cutoff = Date().addingTimeInterval(-TimeInterval(keepDays) * 24 * 60 * 60)

    do {
      try dbQueue.write { db in
        try db.execute(
          sql: "DELETE FROM \(Self.tableName) WHERE date < ?",
          arguments: [cutoff.timeIntervalSince1970]
        )
      }
    } catch {
      Self.logDatabaseError("Failed to cleanup logs", error: error)
    }
  }

  func clear() {
    guard let dbQueue else { return }
    do {
      try dbQueue.write { db in
        try db.execute(sql: "DELETE FROM \(Self.tableName)")
      }
    } catch {
      Self.logDatabaseError("Failed to clear logs", error: error)
    }
  }
}
