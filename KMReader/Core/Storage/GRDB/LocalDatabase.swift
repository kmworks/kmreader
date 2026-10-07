//
// LocalDatabase.swift
//
//

import Foundation
import GRDB

nonisolated enum LocalDatabase {
  static let fileName = "KMReader.sqlite"

  static func open() throws -> DatabaseQueue {
    let url = try databaseURL()
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
      db.add(
        collation: DatabaseCollation("LOCALIZED") { lhs, rhs in
          lhs.localizedStandardCompare(rhs)
        }
      )
    }
    return try DatabaseQueue(path: url.path, configuration: configuration)
  }

  static func migrate(_ writer: any DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = false
    #endif

    migrator.registerMigration("create_runtime_schema_v1") { db in
      try createMarkerTable(db)
      try createInstanceTable(db)
      try createLibraryTable(db)
      try createSeriesTable(db)
      try createBookTable(db)
      try createCollectionTable(db)
      try createReadListTable(db)
      try createCustomFontTable(db)
      try createPendingProgressTable(db)
      try createSavedFilterTable(db)
      try createEpubThemePresetTable(db)
      try createIndexes(db)
    }

    migrator.registerMigration("00002_add_protected_server_flag") { db in
      try db.alter(table: KomgaInstance.databaseTableName) { table in
        table.add(column: "protected", .boolean).notNull().defaults(to: false)
      }
    }

    migrator.registerMigration("00003_add_read_list_offline_policy") { db in
      try db.alter(table: KomgaReadList.databaseTableName) { table in
        table.add(column: "offline_policy_raw", .text).notNull().defaults(to: OfflinePolicy.manual.storageValue)
        table.add(column: "offline_policy_limit", .integer).notNull().defaults(to: 0)
      }
    }

    migrator.registerMigration("00004_add_read_list_book_memberships") { db in
      try createReadListBookMembershipTable(db)
      try backfillReadListBookMemberships(db)
    }

    migrator.registerMigration("00005_add_instance_library_selection") { db in
      try db.alter(table: KomgaInstance.databaseTableName) { table in
        table.add(column: "selected_library_ids_raw", .text)
      }
    }

    migrator.registerMigration("00006_drop_migration_markers") { db in
      try db.execute(sql: "DROP TABLE IF EXISTS local_migration_markers")
    }

    migrator.registerMigration("00007_drop_page_rotations") { db in
      try db.alter(table: KomgaBook.databaseTableName) { table in
        table.drop(column: "page_rotations_raw")
      }
    }

    migrator.registerMigration("00008_add_instance_api_key_id") { db in
      try db.alter(table: KomgaInstance.databaseTableName) { table in
        table.add(column: "api_key_id", .text)
      }
    }

    migrator.registerMigration("00009_add_read_list_reading_states") { db in
      try db.create(table: ReadListReadingState.databaseTableName) { table in
        table.column("instance_id", .text).notNull()
        table.column("read_list_id", .text).notNull()
        table.column("last_read_book_id", .text).notNull()
        table.column("last_read_at", .datetime).notNull()
        table.column("needs_upload", .boolean).notNull().defaults(to: false)
        table.column("is_stopped", .boolean).notNull().defaults(to: false)
        table.primaryKey(["instance_id", "read_list_id"], onConflict: .replace)
      }
    }

    migrator.registerMigration("00010_drop_library_list_counts") { db in
      try db.alter(table: KomgaLibrary.databaseTableName) { table in
        table.drop(column: "collections_count")
        table.drop(column: "readlists_count")
      }
    }

    try migrator.migrate(writer)
  }

  static func databaseURL(fileManager: FileManager = .default) throws -> URL {
    let supportDirectory = try AppStorageDirectory.supportDirectory(fileManager: fileManager)
    return supportDirectory.appendingPathComponent(fileName)
  }

  private static nonisolated func createMarkerTable(_ db: Database) throws {
    try db.create(table: "local_migration_markers", ifNotExists: true) { table in
      table.column("key", .text).primaryKey()
      table.column("state", .text).notNull()
      table.column("message", .text)
      table.column("updated_at", .datetime).notNull()
    }
  }

  private static nonisolated func createInstanceTable(_ db: Database) throws {
    try db.create(table: KomgaInstance.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("name", .text).notNull()
      table.column("server_url", .text).notNull()
      table.column("username", .text).notNull()
      table.column("auth_token", .text).notNull()
      table.column("is_admin", .boolean).notNull()
      table.column("auth_method", .text)
      table.column("created_at", .datetime).notNull()
      table.column("last_used_at", .datetime).notNull()
      table.column("series_last_synced_at", .datetime).notNull()
      table.column("books_last_synced_at", .datetime).notNull()
    }
  }

  private static nonisolated func createLibraryTable(_ db: Database) throws {
    try db.create(table: KomgaLibrary.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("instance_id", .text).notNull()
      table.column("library_id", .text).notNull()
      table.column("name", .text).notNull()
      table.column("created_at", .datetime).notNull()
      table.column("file_size", .double)
      table.column("books_count", .double)
      table.column("series_count", .double)
      table.column("sidecars_count", .double)
      table.column("collections_count", .double)
      table.column("readlists_count", .double)
    }
  }

  private static nonisolated func createSeriesTable(_ db: Database) throws {
    try db.create(table: KomgaSeries.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("series_id", .text).notNull()
      table.column("library_id", .text).notNull()
      table.column("instance_id", .text).notNull()
      table.column("name", .text).notNull()
      table.column("url", .text).notNull()
      table.column("created", .datetime).notNull()
      table.column("last_modified", .datetime).notNull()
      table.column("books_count", .integer).notNull()
      table.column("books_read_count", .integer).notNull()
      table.column("books_unread_count", .integer).notNull()
      table.column("books_in_progress_count", .integer).notNull()
      table.column("metadata_raw", .blob)
      table.column("books_metadata_raw", .blob)
      table.column("meta_title", .text).notNull()
      table.column("meta_title_sort", .text).notNull()
      table.column("meta_publisher_index", .text).notNull()
      table.column("meta_authors_index", .text).notNull()
      table.column("meta_genres_index", .text).notNull()
      table.column("meta_tags_index", .text).notNull()
      table.column("meta_language_index", .text).notNull()
      table.column("is_unavailable", .boolean).notNull()
      table.column("oneshot", .boolean).notNull()
      table.column("download_status_raw", .text).notNull()
      table.column("download_error", .text)
      table.column("download_at", .datetime)
      table.column("downloaded_size", .integer).notNull()
      table.column("downloaded_books", .integer).notNull()
      table.column("pending_books", .integer).notNull()
      table.column("offline_policy_raw", .text).notNull()
      table.column("offline_policy_limit", .integer).notNull()
      table.column("collection_ids_raw", .blob)
    }
  }

  private static nonisolated func createBookTable(_ db: Database) throws {
    try db.create(table: KomgaBook.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("book_id", .text).notNull()
      table.column("series_id", .text).notNull()
      table.column("library_id", .text).notNull()
      table.column("instance_id", .text).notNull()
      table.column("name", .text).notNull()
      table.column("url", .text).notNull()
      table.column("number", .double).notNull()
      table.column("created", .datetime).notNull()
      table.column("last_modified", .datetime).notNull()
      table.column("size_bytes", .integer).notNull()
      table.column("size", .text).notNull()
      table.column("media_raw", .blob)
      table.column("metadata_raw", .blob)
      table.column("read_progress_raw", .blob)
      table.column("media_pages_count", .integer).notNull()
      table.column("media_profile", .text)
      table.column("meta_title", .text).notNull()
      table.column("meta_number", .text).notNull()
      table.column("meta_number_sort", .double).notNull()
      table.column("meta_release_date", .text)
      table.column("progress_page", .integer)
      table.column("progress_completed", .boolean)
      table.column("progress_read_date", .datetime)
      table.column("meta_authors_index", .text).notNull()
      table.column("meta_tags_index", .text).notNull()
      table.column("is_unavailable", .boolean).notNull()
      table.column("oneshot", .boolean).notNull()
      table.column("series_title", .text).notNull()
      table.column("pages_raw", .blob)
      table.column("toc_raw", .blob)
      table.column("web_pub_manifest_raw", .blob)
      table.column("epub_progression_raw", .blob)
      table.column("download_status_raw", .text).notNull()
      table.column("download_error", .text)
      table.column("download_at", .datetime)
      table.column("downloaded_size", .integer).notNull()
      table.column("read_list_ids_raw", .blob)
      table.column("isolate_pages_raw", .blob)
      table.column("page_rotations_raw", .blob)
      table.column("epub_preferences_raw", .text)
    }
  }

  private static nonisolated func createCollectionTable(_ db: Database) throws {
    try db.create(table: KomgaCollection.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("collection_id", .text).notNull()
      table.column("instance_id", .text).notNull()
      table.column("name", .text).notNull()
      table.column("ordered", .boolean).notNull()
      table.column("created_date", .datetime).notNull()
      table.column("last_modified_date", .datetime).notNull()
      table.column("filtered", .boolean).notNull()
      table.column("is_pinned", .boolean).notNull()
      table.column("series_ids_raw", .blob)
    }
  }

  private static nonisolated func createReadListTable(_ db: Database) throws {
    try db.create(table: KomgaReadList.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("read_list_id", .text).notNull()
      table.column("instance_id", .text).notNull()
      table.column("name", .text).notNull()
      table.column("summary", .text).notNull()
      table.column("ordered", .boolean).notNull()
      table.column("created_date", .datetime).notNull()
      table.column("last_modified_date", .datetime).notNull()
      table.column("filtered", .boolean).notNull()
      table.column("is_pinned", .boolean).notNull()
      table.column("book_ids_raw", .blob)
      table.column("download_status_raw", .text).notNull()
      table.column("download_error", .text)
      table.column("download_at", .datetime)
      table.column("downloaded_size", .integer).notNull()
      table.column("downloaded_books", .integer).notNull()
      table.column("pending_books", .integer).notNull()
    }
  }

  private static nonisolated func createReadListBookMembershipTable(_ db: Database) throws {
    try db.create(table: ReadListBookMembership.databaseTableName, ifNotExists: true) { table in
      table.column("instance_id", .text).notNull()
      table.column("read_list_id", .text).notNull()
      table.column("book_id", .text).notNull()
      table.column("position", .integer).notNull()
      table.primaryKey(["instance_id", "read_list_id", "book_id"], onConflict: .replace)
    }
    try db.create(
      index: "idx_read_list_books_book",
      on: ReadListBookMembership.databaseTableName,
      columns: ["instance_id", "book_id"]
    )
    try db.create(
      index: "idx_read_list_books_read_list",
      on: ReadListBookMembership.databaseTableName,
      columns: ["instance_id", "read_list_id", "position"]
    )
  }

  private static nonisolated func backfillReadListBookMemberships(_ db: Database) throws {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT instance_id, read_list_id, book_ids_raw
        FROM \(KomgaReadList.databaseTableName)
        """
    )
    let decoder = JSONDecoder()
    for row in rows {
      let instanceId: String = row["instance_id"]
      let readListId: String = row["read_list_id"]
      let bookIdsRaw: Data? = row["book_ids_raw"]
      let bookIds = bookIdsRaw.flatMap { try? decoder.decode([String].self, from: $0) } ?? []
      for (position, bookId) in bookIds.enumerated() {
        try ReadListBookMembership(
          instanceId: instanceId,
          readListId: readListId,
          bookId: bookId,
          position: position
        ).insert(db)
      }
    }
  }

  private static nonisolated func createCustomFontTable(_ db: Database) throws {
    try db.create(table: CustomFont.databaseTableName, ifNotExists: true) { table in
      table.column("name", .text).primaryKey()
      table.column("path", .text)
      table.column("file_name", .text)
      table.column("file_size", .integer)
      table.column("created_at", .datetime).notNull()
    }
  }

  private static nonisolated func createPendingProgressTable(_ db: Database) throws {
    try db.create(table: PendingProgress.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("instance_id", .text).notNull()
      table.column("book_id", .text).notNull()
      table.column("page", .integer).notNull()
      table.column("completed", .boolean).notNull()
      table.column("created_at", .datetime).notNull()
      table.column("progression_data", .blob)
    }
  }

  private static nonisolated func createSavedFilterTable(_ db: Database) throws {
    try db.create(table: SavedFilter.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("name", .text).notNull()
      table.column("filter_type_raw", .text).notNull()
      table.column("filter_data_json", .text).notNull()
      table.column("created_at", .datetime).notNull()
      table.column("updated_at", .datetime).notNull()
    }
  }

  private static nonisolated func createEpubThemePresetTable(_ db: Database) throws {
    try db.create(table: EpubThemePreset.databaseTableName, ifNotExists: true) { table in
      table.column("id", .text).primaryKey()
      table.column("name", .text).notNull()
      table.column("preferences_json", .text).notNull()
      table.column("created_at", .datetime).notNull()
      table.column("updated_at", .datetime).notNull()
    }
  }

  private static nonisolated func createIndexes(_ db: Database) throws {
    try db.create(index: "idx_libraries_instance", on: KomgaLibrary.databaseTableName, columns: ["instance_id"])
    try db.create(
      index: "idx_series_instance_library", on: KomgaSeries.databaseTableName, columns: ["instance_id", "library_id"])
    try db.create(
      index: "idx_series_sort", on: KomgaSeries.databaseTableName, columns: ["instance_id", "meta_title_sort"])
    try db.create(
      index: "idx_books_instance_library", on: KomgaBook.databaseTableName, columns: ["instance_id", "library_id"])
    try db.create(index: "idx_books_series", on: KomgaBook.databaseTableName, columns: ["instance_id", "series_id"])
    try db.create(
      index: "idx_books_progress", on: KomgaBook.databaseTableName, columns: ["instance_id", "progress_read_date"])
    try db.create(
      index: "idx_books_download", on: KomgaBook.databaseTableName,
      columns: ["instance_id", "download_status_raw", "download_at"])
    try db.create(index: "idx_collections_instance", on: KomgaCollection.databaseTableName, columns: ["instance_id"])
    try db.create(index: "idx_read_lists_instance", on: KomgaReadList.databaseTableName, columns: ["instance_id"])
    try db.create(
      index: "idx_pending_progress_instance", on: PendingProgress.databaseTableName,
      columns: ["instance_id", "created_at"])
    try db.create(
      index: "idx_saved_filters_type", on: SavedFilter.databaseTableName, columns: ["filter_type_raw", "updated_at"])
  }
}
