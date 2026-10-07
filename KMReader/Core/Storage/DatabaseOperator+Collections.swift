//
// DatabaseOperator+Collections.swift
//
//

import Foundation
import GRDB

extension DatabaseOperator {
  func fetchSidebarCollections(instanceId: String, collectionIds: Set<String>) throws -> [SidebarCollectionItem] {
    try read { db in
      let items = try sidebarCollectionRows(db: db, instanceId: instanceId)
      return pinnedFirst(items, isPinned: { $0.isPinned })
        .filter { collectionIds.contains($0.id) }
        .map { SidebarCollectionItem(collectionId: $0.id, name: $0.name, seriesCount: $0.seriesCount) }
    }
  }

  /// Lightweight sidebar rows: only the columns needed for display and sorting
  /// (name ICU order, pinned-first). Avoids decoding the full record.
  private func sidebarCollectionRows(
    db: Database,
    instanceId: String
  ) throws -> [(id: String, name: String, createdDate: Date, lastModifiedDate: Date, isPinned: Bool, seriesCount: Int)]
  {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT collection_id, name, created_date, last_modified_date, is_pinned, series_ids_raw
        FROM \(KomgaCollection.databaseTableName)
        WHERE instance_id = ?
        """,
      arguments: [instanceId]
    )
    let items:
      [(id: String, name: String, createdDate: Date, lastModifiedDate: Date, isPinned: Bool, seriesCount: Int)] =
        rows.map { row in
          let id: String = row["collection_id"]
          let name: String = row["name"]
          let createdDate: Date = row["created_date"]
          let lastModifiedDate: Date = row["last_modified_date"]
          let isPinned: Bool = row["is_pinned"]
          return (
            id: id,
            name: name,
            createdDate: createdDate,
            lastModifiedDate: lastModifiedDate,
            isPinned: isPinned,
            seriesCount: Self.decodeJSONStringArray(row["series_ids_raw"] as? Data).count
          )
        }
    return Self.sortedByBrowseOrder(
      items,
      sort: nil,
      name: { $0.name },
      createdDate: { $0.createdDate },
      lastModifiedDate: { $0.lastModifiedDate }
    )
  }

  func fetchCollectionDisplayItems(instanceId: String) throws -> [CollectionDisplayItem] {
    try read { db in
      try orderedCollections(db: db, instanceId: instanceId).map(Self.makeCollectionDisplayItem)
    }
  }

  /// Fetches all collection ids in one pass: lightweight rows, in-memory ICU
  /// name sort (or date sort), pinned-first. Browse pages slice this array, so
  /// sorting happens once per query change instead of once per page.
  func fetchAllCollectionIds(
    instanceId: String,
    searchText: String,
    sort: String?
  ) -> [String] {
    (try? read { db in
      let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT collection_id, name, created_date, last_modified_date, is_pinned
          FROM \(KomgaCollection.databaseTableName)
          WHERE instance_id = ?
          """,
        arguments: [instanceId]
      )
      let items: [(id: String, name: String, createdDate: Date, lastModifiedDate: Date, isPinned: Bool)] =
        rows.map { row in
          let id: String = row["collection_id"]
          let name: String = row["name"]
          let createdDate: Date = row["created_date"]
          let lastModifiedDate: Date = row["last_modified_date"]
          let isPinned: Bool = row["is_pinned"]
          return (
            id: id,
            name: name,
            createdDate: createdDate,
            lastModifiedDate: lastModifiedDate,
            isPinned: isPinned
          )
        }
      let filtered =
        trimmedSearch.isEmpty
        ? items
        : items.filter { $0.name.localizedStandardContains(trimmedSearch) }
      let sorted = Self.sortedByBrowseOrder(
        filtered,
        sort: sort,
        name: { $0.name },
        createdDate: { $0.createdDate },
        lastModifiedDate: { $0.lastModifiedDate }
      )
      return pinnedFirst(sorted, isPinned: { $0.isPinned }).map { $0.id }
    }) ?? []
  }

  func fetchPinnedCollectionIds(
    instanceId: String,
    searchText: String,
    sort: String?
  ) -> [String] {
    guard !instanceId.isEmpty else { return [] }
    return
      (try? read { db in
        var sql = """
          SELECT collection_id
          FROM \(KomgaCollection.databaseTableName)
          WHERE instance_id = ? AND is_pinned = 1
          """
        var arguments: StatementArguments = [instanceId]
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
          sql += "\nAND name LIKE ? ESCAPE char(92)"
          arguments += StatementArguments([Self.sqlContainsPattern(trimmedSearch)])
        }
        sql += "\nORDER BY \(Self.collectionOrderSQL(sort: sort))"
        return try String.fetchAll(db, sql: sql, arguments: arguments)
      }) ?? []
  }

  func fetchCollectionDisplayItem(collectionId: String, instanceId: String) throws -> CollectionDisplayItem? {
    try read { db in
      try fetchCollectionRecord(db: db, id: collectionId, instanceId: instanceId).map(Self.makeCollectionDisplayItem)
    }
  }

  func upsertCollection(dto: SeriesCollection, instanceId: String) {
    do {
      try write { db in
        let compositeId = CompositeID.generate(instanceId: instanceId, id: dto.id)
        if var existing = try KomgaCollection.fetchOne(db, key: compositeId) {
          applyCollection(dto: dto, to: &existing)
          try save(existing, db: db)
        } else {
          let collection = KomgaCollection(
            id: compositeId,
            collectionId: dto.id,
            instanceId: instanceId,
            name: dto.name,
            ordered: dto.ordered,
            createdDate: dto.createdDate,
            lastModifiedDate: dto.lastModifiedDate,
            filtered: dto.filtered,
            seriesIds: dto.seriesIds
          )
          try save(collection, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert collection: \(error)")
    }
  }

  func deleteCollection(id: String, instanceId: String) {
    _ = try? write { db in
      try KomgaCollection.deleteOne(db, key: CompositeID.generate(instanceId: instanceId, id: id))
    }
  }

  func setCollectionPinned(collectionId: String, instanceId: String, isPinned: Bool) {
    try? write { db in
      guard var collection = try fetchCollectionRecord(db: db, id: collectionId, instanceId: instanceId) else {
        return
      }
      collection.isPinned = isPinned
      try save(collection, db: db)
    }
  }

  func upsertCollections(_ collections: [SeriesCollection], instanceId: String) {
    do {
      try write { db in
        let existingCollections = try fetchCollections(db: db, instanceId: instanceId)
        let existingById = Dictionary(uniqueKeysWithValues: existingCollections.map { ($0.collectionId, $0) })
        for collection in collections {
          var record =
            existingById[collection.id]
            ?? KomgaCollection(
              id: CompositeID.generate(instanceId: instanceId, id: collection.id),
              collectionId: collection.id,
              instanceId: instanceId,
              name: collection.name,
              ordered: collection.ordered,
              createdDate: collection.createdDate,
              lastModifiedDate: collection.lastModifiedDate,
              filtered: collection.filtered,
              seriesIds: collection.seriesIds
            )
          applyCollection(dto: collection, to: &record)
          try save(record, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert collections: \(error)")
    }
  }

  func deleteCollectionsNotIn(_ collectionIds: Set<String>, instanceId: String) -> [String] {
    (try? write { db in
      let existingCollections = try fetchCollections(db: db, instanceId: instanceId)
      var deletedIds: [String] = []
      for collection in existingCollections where !collectionIds.contains(collection.collectionId) {
        try KomgaCollection.deleteOne(db, key: collection.id)
        deletedIds.append(collection.collectionId)
      }
      return deletedIds
    }) ?? []
  }
}

extension DatabaseOperator {
  func fetchSidebarReadLists(instanceId: String, readListIds: Set<String>) throws -> [SidebarReadListItem] {
    try read { db in
      let items = try sidebarReadListRows(db: db, instanceId: instanceId)
      return pinnedFirst(items, isPinned: { $0.isPinned })
        .filter { readListIds.contains($0.id) }
        .map { SidebarReadListItem(readListId: $0.id, name: $0.name, bookCount: $0.bookCount) }
    }
  }

  /// Lightweight sidebar rows: read list columns plus a membership COUNT instead
  /// of decoding book_ids_raw. Membership is rebuilt on every write path, so the
  /// count matches bookIds.count.
  private func sidebarReadListRows(
    db: Database,
    instanceId: String
  ) throws -> [(id: String, name: String, createdDate: Date, lastModifiedDate: Date, isPinned: Bool, bookCount: Int)] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT rl.read_list_id, rl.name, rl.created_date, rl.last_modified_date, rl.is_pinned,
               COUNT(m.book_id) AS book_count
        FROM \(KomgaReadList.databaseTableName) rl
        LEFT JOIN \(ReadListBookMembership.databaseTableName) m
          ON m.read_list_id = rl.read_list_id AND m.instance_id = rl.instance_id
        WHERE rl.instance_id = ?
        GROUP BY rl.id
        """,
      arguments: [instanceId]
    )
    let items: [(id: String, name: String, createdDate: Date, lastModifiedDate: Date, isPinned: Bool, bookCount: Int)] =
      rows.map { row in
        let id: String = row["read_list_id"]
        let name: String = row["name"]
        let createdDate: Date = row["created_date"]
        let lastModifiedDate: Date = row["last_modified_date"]
        let isPinned: Bool = row["is_pinned"]
        let bookCount: Int = row["book_count"]
        return (
          id: id,
          name: name,
          createdDate: createdDate,
          lastModifiedDate: lastModifiedDate,
          isPinned: isPinned,
          bookCount: bookCount
        )
      }
    return Self.sortedByBrowseOrder(
      items,
      sort: nil,
      name: { $0.name },
      createdDate: { $0.createdDate },
      lastModifiedDate: { $0.lastModifiedDate }
    )
  }

  func fetchReadListDisplayItems(instanceId: String) throws -> [ReadListDisplayItem] {
    try read { db in
      try orderedReadLists(db: db, instanceId: instanceId).map(Self.makeReadListDisplayItem)
    }
  }

  /// Same one-pass fetch as fetchAllCollectionIds, for read lists.
  func fetchAllReadListIds(
    instanceId: String,
    searchText: String,
    sort: String?
  ) -> [String] {
    (try? read { db in
      let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT read_list_id, name, summary, created_date, last_modified_date, is_pinned
          FROM \(KomgaReadList.databaseTableName)
          WHERE instance_id = ?
          """,
        arguments: [instanceId]
      )
      let items:
        [(id: String, name: String, summary: String, createdDate: Date, lastModifiedDate: Date, isPinned: Bool)] =
          rows.map { row in
            let id: String = row["read_list_id"]
            let name: String = row["name"]
            let summary: String = row["summary"]
            let createdDate: Date = row["created_date"]
            let lastModifiedDate: Date = row["last_modified_date"]
            let isPinned: Bool = row["is_pinned"]
            return (
              id: id,
              name: name,
              summary: summary,
              createdDate: createdDate,
              lastModifiedDate: lastModifiedDate,
              isPinned: isPinned
            )
          }
      let filtered =
        trimmedSearch.isEmpty
        ? items
        : items.filter {
          $0.name.localizedStandardContains(trimmedSearch)
            || $0.summary.localizedStandardContains(trimmedSearch)
        }
      let sorted = Self.sortedByBrowseOrder(
        filtered,
        sort: sort,
        name: { $0.name },
        createdDate: { $0.createdDate },
        lastModifiedDate: { $0.lastModifiedDate }
      )
      return pinnedFirst(sorted, isPinned: { $0.isPinned }).map { $0.id }
    }) ?? []
  }

  func fetchPinnedReadListIds(
    instanceId: String,
    searchText: String,
    sort: String?
  ) -> [String] {
    guard !instanceId.isEmpty else { return [] }
    return
      (try? read { db in
        var sql = """
          SELECT read_list_id
          FROM \(KomgaReadList.databaseTableName)
          WHERE instance_id = ? AND is_pinned = 1
          """
        var arguments: StatementArguments = [instanceId]
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
          let pattern = Self.sqlContainsPattern(trimmedSearch)
          sql += "\nAND (name LIKE ? ESCAPE char(92) OR summary LIKE ? ESCAPE char(92))"
          arguments += StatementArguments([pattern, pattern])
        }
        sql += "\nORDER BY \(Self.readListOrderSQL(sort: sort))"
        return try String.fetchAll(db, sql: sql, arguments: arguments)
      }) ?? []
  }

  func fetchReadListDisplayItem(readListId: String, instanceId: String) throws -> ReadListDisplayItem? {
    try read { db in
      try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId).map(Self.makeReadListDisplayItem)
    }
  }

  func upsertReadList(dto: ReadList, instanceId: String) {
    do {
      try write { db in
        let compositeId = CompositeID.generate(instanceId: instanceId, id: dto.id)
        if var existing = try KomgaReadList.fetchOne(db, key: compositeId) {
          applyReadList(dto: dto, to: &existing)
          try replaceReadListBookMemberships(db: db, readList: existing)
          syncReadListDownloadStatus(db: db, readList: &existing)
          try save(existing, db: db)
        } else {
          var readList = KomgaReadList(
            id: compositeId,
            readListId: dto.id,
            instanceId: instanceId,
            name: dto.name,
            summary: dto.summary,
            ordered: dto.ordered,
            createdDate: dto.createdDate,
            lastModifiedDate: dto.lastModifiedDate,
            filtered: dto.filtered,
            bookIds: dto.bookIds
          )
          try replaceReadListBookMemberships(db: db, readList: readList)
          syncReadListDownloadStatus(db: db, readList: &readList)
          try save(readList, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert read list: \(error)")
    }
  }

  func deleteReadList(id: String, instanceId: String) {
    _ = try? write { db in
      try deleteReadListBookMemberships(db: db, readListId: id, instanceId: instanceId)
      try KomgaReadList.deleteOne(db, key: CompositeID.generate(instanceId: instanceId, id: id))
    }
  }

  func replaceReadListBookIds(readListId: String, instanceId: String, bookIds: [String]) {
    try? write { db in
      guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
        return
      }
      readList.bookIds = bookIds
      try replaceReadListBookMemberships(db: db, readList: readList)
      syncReadListDownloadStatus(db: db, readList: &readList)
      try save(readList, db: db)
    }
  }

  func setReadListPinned(readListId: String, instanceId: String, isPinned: Bool) {
    try? write { db in
      guard var readList = try fetchReadListRecord(db: db, id: readListId, instanceId: instanceId) else {
        return
      }
      readList.isPinned = isPinned
      try save(readList, db: db)
    }
  }

  @discardableResult
  func upsertReadLists(_ readLists: [ReadList], instanceId: String) -> [String] {
    var automaticPolicyReadListIds = Set<String>()
    do {
      try write { db in
        let existingReadLists = try fetchReadLists(db: db, instanceId: instanceId)
        let existingById = Dictionary(uniqueKeysWithValues: existingReadLists.map { ($0.readListId, $0) })
        for readList in readLists {
          var record =
            existingById[readList.id]
            ?? KomgaReadList(
              id: CompositeID.generate(instanceId: instanceId, id: readList.id),
              readListId: readList.id,
              instanceId: instanceId,
              name: readList.name,
              summary: readList.summary,
              ordered: readList.ordered,
              createdDate: readList.createdDate,
              lastModifiedDate: readList.lastModifiedDate,
              filtered: readList.filtered,
              bookIds: readList.bookIds
            )
          applyReadList(dto: readList, to: &record)
          try replaceReadListBookMemberships(db: db, readList: record)
          syncReadListDownloadStatus(db: db, readList: &record)
          if record.offlinePolicy != .manual {
            automaticPolicyReadListIds.insert(record.readListId)
          }
          try save(record, db: db)
        }
      }
    } catch {
      logger.error("Failed to upsert read lists: \(error)")
    }
    return automaticPolicyReadListIds.sorted()
  }

  func deleteReadListsNotIn(_ readListIds: Set<String>, instanceId: String) -> [String] {
    (try? write { db in
      let existingReadLists = try fetchReadLists(db: db, instanceId: instanceId)
      var deletedIds: [String] = []
      for readList in existingReadLists where !readListIds.contains(readList.readListId) {
        try deleteReadListBookMemberships(db: db, readListId: readList.readListId, instanceId: instanceId)
        try KomgaReadList.deleteOne(db, key: readList.id)
        deletedIds.append(readList.readListId)
      }
      return deletedIds
    }) ?? []
  }
}

extension DatabaseOperator {
  func orderedCollections(
    db: Database,
    instanceId: String,
    searchText: String = "",
    sort: String? = nil
  ) throws -> [KomgaCollection] {
    let collections = try fetchCollections(db: db, instanceId: instanceId).filter { collection in
      searchText.isEmpty || collection.name.localizedStandardContains(searchText)
    }
    return pinnedFirst(sortCollections(collections, sort: sort), isPinned: { $0.isPinned })
  }

  func orderedReadLists(
    db: Database,
    instanceId: String,
    searchText: String = "",
    sort: String? = nil
  ) throws -> [KomgaReadList] {
    let readLists = try fetchReadLists(db: db, instanceId: instanceId).filter { readList in
      searchText.isEmpty
        || readList.name.localizedStandardContains(searchText)
        || readList.summary.localizedStandardContains(searchText)
    }
    return pinnedFirst(sortReadLists(readLists, sort: sort), isPinned: { $0.isPinned })
  }

  func applyCollection(dto: SeriesCollection, to existing: inout KomgaCollection) {
    if existing.name != dto.name { existing.name = dto.name }
    if existing.ordered != dto.ordered { existing.ordered = dto.ordered }
    if existing.filtered != dto.filtered { existing.filtered = dto.filtered }
    if existing.lastModifiedDate != dto.lastModifiedDate {
      existing.lastModifiedDate = dto.lastModifiedDate
    }
    if existing.seriesIds != dto.seriesIds { existing.seriesIds = dto.seriesIds }
  }

  func applyReadList(dto: ReadList, to existing: inout KomgaReadList) {
    if existing.name != dto.name { existing.name = dto.name }
    if existing.summary != dto.summary { existing.summary = dto.summary }
    if existing.ordered != dto.ordered { existing.ordered = dto.ordered }
    if existing.filtered != dto.filtered { existing.filtered = dto.filtered }
    if existing.lastModifiedDate != dto.lastModifiedDate {
      existing.lastModifiedDate = dto.lastModifiedDate
    }
    if existing.bookIds != dto.bookIds { existing.bookIds = dto.bookIds }
  }

  func replaceReadListBookMemberships(db: Database, readList: KomgaReadList) throws {
    try deleteReadListBookMemberships(
      db: db,
      readListId: readList.readListId,
      instanceId: readList.instanceId
    )
    for (position, bookId) in readList.bookIds.enumerated() {
      try ReadListBookMembership(
        instanceId: readList.instanceId,
        readListId: readList.readListId,
        bookId: bookId,
        position: position
      ).insert(db)
    }
  }

  func deleteReadListBookMemberships(db: Database, readListId: String, instanceId: String) throws {
    try db.execute(
      sql: """
        DELETE FROM \(ReadListBookMembership.databaseTableName)
        WHERE instance_id = ?
        AND read_list_id = ?
        """,
      arguments: [instanceId, readListId]
    )
  }

  func fetchReadListBookMemberships(
    db: Database,
    instanceId: String,
    readListIds: [String]? = nil,
    bookIds: [String]? = nil
  ) throws -> [ReadListBookMembership] {
    if let readListIds, readListIds.isEmpty { return [] }
    if let bookIds, bookIds.isEmpty { return [] }

    let chunkSize =
      readListIds != nil && bookIds != nil
      ? max(1, Self.recordFetchChunkSize / 2)
      : Self.recordFetchChunkSize
    let readListChunks: [[String]?] =
      if let readListIds {
        Self.chunkedSQLValues(readListIds, chunkSize: chunkSize).map(Optional.some)
      } else {
        [nil]
      }
    let bookChunks: [[String]?] =
      if let bookIds {
        Self.chunkedSQLValues(bookIds, chunkSize: chunkSize).map(Optional.some)
      } else {
        [nil]
      }

    var memberships: [ReadListBookMembership] = []
    for readListChunk in readListChunks {
      for bookChunk in bookChunks {
        var sql = """
          SELECT *
          FROM \(ReadListBookMembership.databaseTableName)
          WHERE instance_id = ?
          """
        var arguments: StatementArguments = [instanceId]
        if let readListChunk {
          Self.appendSQLInFilter(column: "read_list_id", values: readListChunk, sql: &sql, arguments: &arguments)
        }
        if let bookChunk {
          Self.appendSQLInFilter(column: "book_id", values: bookChunk, sql: &sql, arguments: &arguments)
        }
        memberships.append(contentsOf: try ReadListBookMembership.fetchAll(db, sql: sql, arguments: arguments))
      }
    }
    return memberships.sorted {
      if $0.readListId == $1.readListId {
        return $0.position < $1.position
      }
      return $0.readListId < $1.readListId
    }
  }

  func fetchReadListIdsContainingBooks(db: Database, instanceId: String, bookIds: [String]) throws -> [String] {
    guard !bookIds.isEmpty else { return [] }
    var readListIds = Set<String>()
    for bookIds in Self.chunkedSQLValues(bookIds, chunkSize: Self.recordFetchChunkSize) {
      var sql = """
        SELECT DISTINCT read_list_id
        FROM \(ReadListBookMembership.databaseTableName)
        WHERE instance_id = ?
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "book_id", values: bookIds, sql: &sql, arguments: &arguments)
      readListIds.formUnion(try String.fetchAll(db, sql: sql, arguments: arguments))
    }
    return readListIds.sorted()
  }

  func fetchReadListsAndMembershipsContainingBooks(
    db: Database,
    instanceId: String,
    bookIds: [String]
  ) throws -> (readLists: [KomgaReadList], memberships: [ReadListBookMembership]) {
    let readListIds = try fetchReadListIdsContainingBooks(db: db, instanceId: instanceId, bookIds: bookIds)
    guard !readListIds.isEmpty else { return ([], []) }
    return (
      try fetchReadListsByIds(db: db, ids: readListIds, instanceId: instanceId),
      try fetchReadListBookMemberships(db: db, instanceId: instanceId, readListIds: readListIds)
    )
  }

  func fetchReadListsByIds(db: Database, ids: [String], instanceId: String) throws -> [KomgaReadList] {
    guard !ids.isEmpty else { return [] }
    var readLists: [KomgaReadList] = []
    for ids in Self.chunkedSQLValues(ids, chunkSize: Self.recordFetchChunkSize) {
      var sql = """
        SELECT *
        FROM \(KomgaReadList.databaseTableName)
        WHERE instance_id = ?
        """
      var arguments: StatementArguments = [instanceId]
      Self.appendSQLInFilter(column: "read_list_id", values: ids, sql: &sql, arguments: &arguments)
      readLists.append(contentsOf: try KomgaReadList.fetchAll(db, sql: sql, arguments: arguments))
    }
    return Self.orderedByIds(readLists, ids: ids, id: \.readListId)
  }

  nonisolated static func chunkedSQLValues(_ values: [String], chunkSize: Int) -> [[String]] {
    let uniqueValues = Array(Set(values))
    guard !uniqueValues.isEmpty else { return [] }
    let safeChunkSize = max(1, chunkSize)
    return stride(from: 0, to: uniqueValues.count, by: safeChunkSize).map { start in
      let end = min(start + safeChunkSize, uniqueValues.count)
      return Array(uniqueValues[start..<end])
    }
  }

  nonisolated static func makeCollectionDisplayItem(_ collection: KomgaCollection) -> CollectionDisplayItem {
    CollectionDisplayItem(
      collectionId: collection.collectionId,
      instanceId: collection.instanceId,
      name: collection.name,
      ordered: collection.ordered,
      createdDate: collection.createdDate,
      lastModifiedDate: collection.lastModifiedDate,
      filtered: collection.filtered,
      isPinned: collection.isPinned,
      seriesIds: collection.seriesIds
    )
  }

  nonisolated static func makeReadListDisplayItem(_ readList: KomgaReadList) -> ReadListDisplayItem {
    ReadListDisplayItem(
      readListId: readList.readListId,
      instanceId: readList.instanceId,
      name: readList.name,
      summary: readList.summary,
      ordered: readList.ordered,
      createdDate: readList.createdDate,
      lastModifiedDate: readList.lastModifiedDate,
      filtered: readList.filtered,
      isPinned: readList.isPinned,
      bookIds: readList.bookIds,
      downloadStatus: readList.downloadStatus,
      offlinePolicy: readList.offlinePolicy,
      offlinePolicyLimit: readList.offlinePolicyLimit
    )
  }

  nonisolated func pinnedFirst<T>(_ items: [T], isPinned: (T) -> Bool) -> [T] {
    items.filter(isPinned) + items.filter { !isPinned($0) }
  }

  /// Shared browse-order comparator: createdDate / lastModifiedDate are
  /// numeric; the default name branch uses locale-aware ICU comparison
  /// (localizedStandardCompare), matching the LOCALIZED SQL collation.
  nonisolated static func sortedByBrowseOrder<T>(
    _ items: [T],
    sort: String?,
    name: (T) -> String,
    createdDate: (T) -> Date,
    lastModifiedDate: (T) -> Date
  ) -> [T] {
    let isAscending = sort?.contains("desc") != true
    if sort?.contains("createdDate") == true {
      return items.sorted {
        isAscending ? createdDate($0) < createdDate($1) : createdDate($0) > createdDate($1)
      }
    }
    if sort?.contains("lastModifiedDate") == true {
      return items.sorted {
        isAscending ? lastModifiedDate($0) < lastModifiedDate($1) : lastModifiedDate($0) > lastModifiedDate($1)
      }
    }
    return items.sorted {
      let result = name($0).localizedStandardCompare(name($1))
      return isAscending ? result == .orderedAscending : result == .orderedDescending
    }
  }

  nonisolated func sortCollections(_ collections: [KomgaCollection], sort: String?) -> [KomgaCollection] {
    Self.sortedByBrowseOrder(
      collections,
      sort: sort,
      name: { $0.name },
      createdDate: { $0.createdDate },
      lastModifiedDate: { $0.lastModifiedDate }
    )
  }

  nonisolated func sortReadLists(_ readLists: [KomgaReadList], sort: String?) -> [KomgaReadList] {
    Self.sortedByBrowseOrder(
      readLists,
      sort: sort,
      name: { $0.name },
      createdDate: { $0.createdDate },
      lastModifiedDate: { $0.lastModifiedDate }
    )
  }

  nonisolated static func collectionOrderSQL(sort: String?) -> String {
    let direction = sort?.contains("desc") == true ? "DESC" : "ASC"
    if sort?.contains("createdDate") == true {
      return "created_date \(direction), id ASC"
    }
    if sort?.contains("lastModifiedDate") == true {
      return "last_modified_date \(direction), id ASC"
    }
    return "name COLLATE LOCALIZED \(direction), id ASC"
  }

  nonisolated static func readListOrderSQL(sort: String?) -> String {
    let direction = sort?.contains("desc") == true ? "DESC" : "ASC"
    if sort?.contains("createdDate") == true {
      return "created_date \(direction), id ASC"
    }
    if sort?.contains("lastModifiedDate") == true {
      return "last_modified_date \(direction), id ASC"
    }
    return "name COLLATE LOCALIZED \(direction), id ASC"
  }
}
