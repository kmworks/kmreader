//
// SyncService.swift
//
//

import Foundation
import OSLog

extension Notification.Name {
  static let sidebarProjectionDidChange = Notification.Name("SidebarProjectionDidChange")
}

nonisolated enum SyncService {

  private static let logger = AppLogger(.sync)
  private static let syncPageSize = 1000

  static func postSidebarProjectionDidChange(instanceId: String) async {
    await MainActor.run {
      NotificationCenter.default.post(
        name: .sidebarProjectionDidChange,
        object: nil,
        userInfo: ["instanceId": instanceId]
      )
    }
  }

  static func syncAll(instanceId: String) async {
    logger.info("🔄 Starting full sync for instance: \(instanceId)")
    await syncLibraries(instanceId: instanceId)
    await syncCollections(instanceId: instanceId)
    await syncReadLists(instanceId: instanceId)
    await syncDashboard(instanceId: instanceId)
    logger.info("✅ Full sync completed for instance: \(instanceId)")
  }

  static func syncLibraries(instanceId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      let libraries = try await LibraryService.getLibraries()
      let libraryInfos = libraries.map { LibraryInfo(id: $0.id, name: $0.name) }
      try await database.replaceLibraries(libraryInfos, for: instanceId)
      await postSidebarProjectionDidChange(instanceId: instanceId)
      logger.info("📚 Synced \(libraries.count) libraries")
    } catch {
      logger.error("❌ Failed to sync libraries: \(error)")
    }
  }

  static func syncCollections(instanceId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      var page = 0
      var hasMore = true
      var remoteCollectionIds = Set<String>()
      while hasMore {
        let result: Page<SeriesCollection> = try await CollectionService.getCollections(
          page: page, size: syncPageSize)
        remoteCollectionIds.formUnion(result.content.map(\.id))
        await database.upsertCollections(result.content, instanceId: instanceId)
        hasMore = !result.last
        page += 1
      }
      let deletedCollectionIds = await database.deleteCollectionsNotIn(
        remoteCollectionIds,
        instanceId: instanceId
      )
      await ContentProjectionNotifier.postCollectionsDidChange(collectionIds: deletedCollectionIds)
      await postSidebarProjectionDidChange(instanceId: instanceId)
      if !deletedCollectionIds.isEmpty {
        logger.info("🧹 Removed \(deletedCollectionIds.count) stale collections")
      }
      logger.info("📂 Synced collections")
    } catch {
      logger.error("❌ Failed to sync collections: \(error)")
    }
  }

  static func syncReadLists(instanceId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      var page = 0
      var hasMore = true
      var remoteReadListIds = Set<String>()
      var automaticPolicyReadListIds = Set<String>()
      while hasMore {
        let result: Page<ReadList> = try await ReadListService.getReadLists(
          page: page, size: syncPageSize)
        remoteReadListIds.formUnion(result.content.map(\.id))
        let pagePolicyReadListIds = await database.upsertReadLists(result.content, instanceId: instanceId)
        automaticPolicyReadListIds.formUnion(pagePolicyReadListIds)
        hasMore = !result.last
        page += 1
      }
      await syncAutomaticReadListBooks(Array(automaticPolicyReadListIds), instanceId: instanceId)
      let deletedReadListIds = await database.deleteReadListsNotIn(
        remoteReadListIds,
        instanceId: instanceId
      )
      await ContentProjectionNotifier.postReadListsDidChange(readListIds: deletedReadListIds)
      await postSidebarProjectionDidChange(instanceId: instanceId)
      if !deletedReadListIds.isEmpty {
        logger.info("🧹 Removed \(deletedReadListIds.count) stale read lists")
      }
      logger.info("📖 Synced readlists")
    } catch {
      logger.error("❌ Failed to sync readlists: \(error)")
    }
  }

  static func syncSeries(libraryId: String, instanceId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      var page = 0
      var hasMore = true
      let filters = SeriesSearchFilters(libraryIds: [libraryId])
      let condition = SeriesSearch.buildCondition(filters: filters)
      let search = SeriesSearch(condition: condition)
      while hasMore {
        let result = try await SeriesService.getSeriesList(
          search: search, page: page, size: syncPageSize)
        await database.upsertSeriesList(result.content, instanceId: instanceId)
        hasMore = !result.last
        page += 1
      }
      logger.info("📚 Synced series for library \(libraryId)")
    } catch {
      logger.error("❌ Failed to sync series for library \(libraryId): \(error)")
    }
  }

  static func syncSeriesPage(
    libraryIds: [String]?,
    page: Int,
    size: Int,
    searchTerm: String?,
    browseOpts: SeriesBrowseOptions?
  ) async throws -> Page<Series> {
    let database = try await DatabaseOperator.database()
    let result = try await SeriesService.getSeries(
      libraryIds: libraryIds,
      page: page,
      size: size,
      browseOpts: browseOpts ?? SeriesBrowseOptions(),
      searchTerm: searchTerm
    )

    let instanceId = AppConfig.current.instanceId
    await database.upsertSeriesList(result.content, instanceId: instanceId)

    return result
  }

  static func syncSeriesDetail(seriesId: String) async throws -> Series {
    let database = try await DatabaseOperator.database()
    do {
      let series = try await SeriesService.getOneSeries(id: seriesId)
      let instanceId = AppConfig.current.instanceId
      await database.upsertSeries(dto: series, instanceId: instanceId)
      return series
    } catch APIError.notFound {
      let instanceId = AppConfig.current.instanceId
      let item = try? await database.fetchSeriesDisplayItem(seriesId: seriesId, instanceId: instanceId)
      await database.deleteSeries(id: seriesId, instanceId: instanceId)
      await ContentProjectionNotifier.postSeriesDidChange(
        seriesId: seriesId,
        libraryId: item?.series.libraryId,
        refreshDelay: 0
      )
      throw APIError.notFound(message: "Series not found", url: nil, response: nil, request: nil)
    }
  }

  static func syncNewSeries(libraryIds: [String]?, page: Int, size: Int) async throws -> Page<Series> {
    let database = try await DatabaseOperator.database()
    let result = try await SeriesService.getNewSeries(
      libraryIds: libraryIds, page: page, size: size)
    let instanceId = AppConfig.current.instanceId
    await database.upsertSeriesList(result.content, instanceId: instanceId)
    return result
  }

  static func syncUpdatedSeries(libraryIds: [String]?, page: Int, size: Int) async throws -> Page<Series> {
    let database = try await DatabaseOperator.database()
    let result = try await SeriesService.getUpdatedSeries(
      libraryIds: libraryIds, page: page, size: size)
    let instanceId = AppConfig.current.instanceId
    await database.upsertSeriesList(result.content, instanceId: instanceId)
    return result
  }

  static func syncBooks(
    seriesId: String,
    page: Int,
    size: Int,
    browseOpts: BookBrowseOptions? = nil,
  ) async throws -> Page<Book> {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getBooks(
      seriesId: seriesId,
      page: page,
      size: size,
      browseOpts: browseOpts ?? BookBrowseOptions()
    )
    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)
    return result
  }

  static func syncBooksList(
    search: BookSearch,
    page: Int,
    size: Int,
    sort: String?
  ) async throws -> Page<Book> {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getBooksList(
      search: search,
      page: page,
      size: size,
      sort: sort.map { [$0] }
    )

    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)

    return result
  }

  static func syncBrowseBooks(
    libraryIds: [String]?,
    page: Int,
    size: Int,
    searchTerm: String?,
    browseOpts: BookBrowseOptions
  ) async throws -> Page<Book> {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getBrowseBooks(
      libraryIds: libraryIds,
      page: page,
      size: size,
      browseOpts: browseOpts,
      searchTerm: searchTerm
    )

    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)

    return result
  }

  static func syncBooksOnDeck(libraryIds: [String]?, page: Int, size: Int) async throws -> Page<Book> {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getBooksOnDeck(
      libraryIds: libraryIds, page: page, size: size)
    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)
    return result
  }

  static func syncRecentlyReadBooks(libraryIds: [String]?, page: Int, size: Int) async throws -> Page<Book> {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getRecentlyReadBooks(
      libraryIds: libraryIds, page: page, size: size)
    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)
    return result
  }

  static func syncRecentlyAddedBooks(libraryIds: [String]?, page: Int, size: Int) async throws -> Page<
    Book
  > {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getRecentlyAddedBooks(
      libraryIds: libraryIds, page: page, size: size)
    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)
    return result
  }

  static func syncRecentlyReleasedBooks(libraryIds: [String]?, page: Int, size: Int) async throws -> Page<
    Book
  > {
    let database = try await DatabaseOperator.database()
    let result = try await BookService.getRecentlyReleasedBooks(
      libraryIds: libraryIds, page: page, size: size)
    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)
    return result
  }

  /// Sync all books for a series (all pages) - used before offline policy operations
  static func syncAllSeriesBooks(seriesId: String) async throws {
    let database = try await DatabaseOperator.database()
    let instanceId = AppConfig.current.instanceId
    var page = 0
    var hasMore = true

    while hasMore {
      let result = try await BookService.getBooks(
        seriesId: seriesId,
        page: page,
        size: syncPageSize,
        browseOpts: BookBrowseOptions()
      )
      await database.upsertBooks(result.content, instanceId: instanceId)
      hasMore = !result.last
      page += 1
    }
    logger.info("📚 Synced all books for series \(seriesId)")
  }

  /// Sync all books for a readlist (all pages) - used before offline policy operations
  static func syncAllReadListBooks(readListId: String, instanceId: String = AppConfig.current.instanceId) async throws {
    let database = try await DatabaseOperator.database()
    var page = 0
    var hasMore = true
    var bookIds: [String] = []

    while hasMore {
      let result = try await ReadListService.getReadListBooks(
        readListId: readListId,
        page: page,
        size: syncPageSize,
        browseOpts: ReadListBookBrowseOptions(),
        libraryIds: nil
      )
      await database.upsertBooks(result.content, instanceId: instanceId)
      bookIds.append(contentsOf: result.content.map(\.id))
      hasMore = !result.last
      page += 1
    }
    await database.replaceReadListBookIds(readListId: readListId, instanceId: instanceId, bookIds: bookIds)
    logger.info("📖 Synced all books for readlist \(readListId)")
  }

  static func syncBook(bookId: String) async throws -> Book {
    let database = try await DatabaseOperator.database()
    do {
      let book = try await BookService.getBook(id: bookId)
      let instanceId = AppConfig.current.instanceId
      await database.upsertBook(dto: book, instanceId: instanceId)
      return book
    } catch APIError.notFound {
      let instanceId = AppConfig.current.instanceId
      let item = try? await database.fetchBookDisplayItem(bookId: bookId, instanceId: instanceId)
      await database.deleteBook(id: bookId, instanceId: instanceId)
      await ContentProjectionNotifier.postBookAndSeriesDidChange(
        bookId: bookId,
        instanceId: instanceId,
        seriesId: item?.seriesId,
        libraryId: item?.book.libraryId,
        refreshDelay: 0
      )
      throw APIError.notFound(message: "Book not found", url: nil, response: nil, request: nil)
    }
  }

  static func syncBookAndSeries(bookId: String, seriesId: String) async throws {
    let database = try await DatabaseOperator.database()
    async let bookTask = BookService.getBook(id: bookId)
    async let seriesTask = SeriesService.getOneSeries(id: seriesId)

    let book = try await bookTask
    let series = try await seriesTask

    let instanceId = AppConfig.current.instanceId
    await database.upsertBook(dto: book, instanceId: instanceId)
    await database.upsertSeries(dto: series, instanceId: instanceId)
  }

  /// Batch sync multiple books and series concurrently with a single commit
  static func syncVisitedItems(bookIds: Set<String>, seriesIds: Set<String>) async {
    guard !bookIds.isEmpty || !seriesIds.isEmpty else { return }

    do {
      let database = try await DatabaseOperator.database()
      let instanceId = AppConfig.current.instanceId

      // Fetch all books and series concurrently
      await withTaskGroup(of: Void.self) { group in
        for bookId in bookIds {
          group.addTask {
            do {
              let book = try await BookService.getBook(id: bookId)
              await database.upsertBook(dto: book, instanceId: instanceId)
            } catch {
              // Silently ignore individual fetch failures
            }
          }
        }

        for seriesId in seriesIds {
          group.addTask {
            do {
              let series = try await SeriesService.getOneSeries(id: seriesId)
              await database.upsertSeries(dto: series, instanceId: instanceId)
            } catch {
              // Silently ignore individual fetch failures
            }
          }
        }
      }

      // Single commit after all fetches complete
    } catch {
      logger.error("❌ Failed to sync visited items: \(error)")
    }
  }

  static func syncCollections(
    libraryIds: [String]?,
    page: Int,
    size: Int,
    sort: String?,
    search: String?
  ) async throws -> Page<SeriesCollection> {
    let database = try await DatabaseOperator.database()
    let result = try await CollectionService.getCollections(
      libraryIds: libraryIds,
      page: page,
      size: size,
      sort: sort,
      search: search
    )
    let instanceId = AppConfig.current.instanceId
    await database.upsertCollections(result.content, instanceId: instanceId)
    return result
  }

  static func syncCollection(id: String) async throws -> SeriesCollection {
    let database = try await DatabaseOperator.database()
    do {
      let collection = try await CollectionService.getCollection(id: id)
      let instanceId = AppConfig.current.instanceId
      await database.upsertCollection(dto: collection, instanceId: instanceId)
      return collection
    } catch APIError.notFound {
      let instanceId = AppConfig.current.instanceId
      await database.deleteCollection(id: id, instanceId: instanceId)
      await ContentProjectionNotifier.postCollectionDidChange(collectionId: id, refreshDelay: 0)
      throw APIError.notFound(message: "Collection not found", url: nil, response: nil, request: nil)
    }
  }

  static func syncSeriesCollections(seriesId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      let collections = try await SeriesService.getSeriesCollections(seriesId: seriesId)
      let instanceId = AppConfig.current.instanceId
      await database.upsertCollections(collections, instanceId: instanceId)
      // Update the series' cached collectionIds
      let collectionIds = collections.map { $0.id }
      await database.updateSeriesCollectionIds(
        seriesId: seriesId, collectionIds: collectionIds, instanceId: instanceId)
    } catch {
      logger.error("❌ Failed to sync series collections: \(error)")
    }
  }

  static func syncCollectionSeries(
    collectionId: String,
    page: Int,
    size: Int,
    browseOpts: CollectionSeriesBrowseOptions,
    libraryIds: [String]?
  ) async throws -> Page<Series> {
    let database = try await DatabaseOperator.database()
    let result = try await CollectionService.getCollectionSeries(
      collectionId: collectionId,
      page: page,
      size: size,
      browseOpts: browseOpts,
      libraryIds: libraryIds
    )
    let instanceId = AppConfig.current.instanceId
    await database.upsertSeriesList(result.content, instanceId: instanceId)
    return result
  }

  static func syncReadLists(
    libraryIds: [String]?,
    page: Int,
    size: Int,
    sort: String?,
    search: String?
  ) async throws -> Page<ReadList> {
    let database = try await DatabaseOperator.database()
    let result = try await ReadListService.getReadLists(
      libraryIds: libraryIds,
      page: page,
      size: size,
      sort: sort,
      search: search
    )
    let instanceId = AppConfig.current.instanceId
    let automaticPolicyReadListIds = await database.upsertReadLists(result.content, instanceId: instanceId)
    await syncAutomaticReadListBooks(automaticPolicyReadListIds)
    return result
  }

  static func syncReadList(id: String) async throws -> ReadList {
    let database = try await DatabaseOperator.database()
    do {
      let readList = try await ReadListService.getReadList(id: id)
      let instanceId = AppConfig.current.instanceId
      await database.upsertReadList(dto: readList, instanceId: instanceId)
      let item = try? await database.fetchReadListDisplayItem(readListId: id, instanceId: instanceId)
      if item?.offlinePolicy != .manual {
        try? await syncAllReadListBooks(readListId: id)
      }
      return readList
    } catch APIError.notFound {
      let instanceId = AppConfig.current.instanceId
      await database.deleteReadList(id: id, instanceId: instanceId)
      await ContentProjectionNotifier.postReadListDidChange(readListId: id, refreshDelay: 0)
      throw APIError.notFound(message: "Read list not found", url: nil, response: nil, request: nil)
    }
  }

  static func syncReadListBooks(
    readListId: String,
    page: Int,
    size: Int,
    browseOpts: ReadListBookBrowseOptions,
    libraryIds: [String]?
  ) async throws -> Page<Book> {
    let database = try await DatabaseOperator.database()
    let result = try await ReadListService.getReadListBooks(
      readListId: readListId,
      page: page,
      size: size,
      browseOpts: browseOpts,
      libraryIds: libraryIds
    )
    let instanceId = AppConfig.current.instanceId
    await database.upsertBooks(result.content, instanceId: instanceId)
    return result
  }

  static func syncBookReadLists(bookId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      let readLists = try await BookService.getReadListsForBook(bookId: bookId)
      let instanceId = AppConfig.current.instanceId
      await database.upsertReadLists(readLists, instanceId: instanceId)
      // Update the book's cached readListIds
      let readListIds = readLists.map { $0.id }
      await database.updateBookReadListIds(
        bookId: bookId, readListIds: readListIds, instanceId: instanceId)
    } catch {
      logger.error("❌ Failed to sync book read lists: \(error)")
    }
  }

  static func syncAutomaticReadListBooks(
    _ readListIds: [String],
    instanceId: String = AppConfig.current.instanceId
  ) async {
    for readListId in Set(readListIds).sorted() {
      do {
        try await syncAllReadListBooks(readListId: readListId, instanceId: instanceId)
      } catch {
        logger.error("❌ Failed to sync automatic read-list books \(readListId): \(error)")
      }
    }
  }

  static func syncDashboard(instanceId: String) async {
    guard let database = await DatabaseOperator.databaseIfConfigured() else {
      logger.warning("⚠️ Failed to get database operator for dashboard sync")
      return
    }

    let libraryIds = await database.fetchLibraries(instanceId: instanceId).map(\.id)
    _ = try? await syncBooksOnDeck(libraryIds: libraryIds, page: 0, size: 20)
    _ = try? await syncRecentlyAddedBooks(libraryIds: libraryIds, page: 0, size: 20)
    _ = try? await syncRecentlyReadBooks(libraryIds: libraryIds, page: 0, size: 20)
    _ = try? await syncRecentlyReleasedBooks(libraryIds: libraryIds, page: 0, size: 20)
    _ = try? await syncNewSeries(libraryIds: libraryIds, page: 0, size: 20)
    _ = try? await syncUpdatedSeries(libraryIds: libraryIds, page: 0, size: 20)
  }

  // MARK: - Cleanup

  static func clearInstanceData(instanceId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      await database.clearInstanceData(instanceId: instanceId)
    } catch {
      logger.error("❌ Failed to clear instance data: \(error)")
    }
  }
}
