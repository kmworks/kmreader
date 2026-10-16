//
// ReaderContentService.swift
//
//

import Foundation

@MainActor
struct ReaderContentService {
  private let logger = AppLogger(.reader)

  func resolveBook(
    bookId: String,
    currentBook: () -> Book?,
    fallbackBook: Book
  ) async -> Book? {
    var resolvedBook: Book?
    let database = await DatabaseOperator.databaseIfConfigured()
    if let currentBook = currentBook(), currentBook.id == bookId {
      resolvedBook = currentBook
    } else if let cachedBook = await database?.fetchBook(id: bookId) {
      resolvedBook = cachedBook
    } else if fallbackBook.id == bookId {
      resolvedBook = fallbackBook
    }

    if !AppConfig.isOffline {
      if let syncedBook = try? await SyncService.syncBook(bookId: bookId) {
        resolvedBook = syncedBook
      }
    }
    return resolvedBook
  }

  func refreshManifestIfNeeded(for book: Book) async {
    let isBookDownloaded = await OfflineManager.shared.isBookDownloaded(bookId: book.id)

    // Refresh Divina manifest only when online and the book is not downloaded offline.
    if !AppConfig.isOffline, !isBookDownloaded {
      do {
        let manifest = try await BookService.getBookManifest(id: book.id)
        let toc = await ReaderManifestService(bookId: book.id).parseTOC(manifest: manifest)
        let database = await DatabaseOperator.databaseIfConfigured()
        await database?.updateBookTOC(bookId: book.id, toc: toc)
      } catch {
        // Silently fail - we'll use cached manifest
      }
    }
  }

  func loadSeries(for book: Book) async -> Series? {
    let database = await DatabaseOperator.databaseIfConfigured()
    var series = await database?.fetchSeries(id: book.seriesId)
    if series == nil && !AppConfig.isOffline {
      series = try? await SyncService.syncSeriesDetail(seriesId: book.seriesId)
    }
    return series
  }

  func loadPages(for book: Book) async throws -> [BookPage] {
    let database = await DatabaseOperator.databaseIfConfigured()
    let storedPages: [BookPage]
    let shouldRefreshCachedPages: Bool
    if let localPages = await database?.fetchPages(id: book.id) {
      storedPages = localPages
      shouldRefreshCachedPages = !AppConfig.offlineFirstReading && !AppConfig.isOffline
    } else if !AppConfig.isOffline {
      storedPages = try await BookService.getBookPages(id: book.id)
      await database?.updateBookPages(bookId: book.id, pages: storedPages)
      shouldRefreshCachedPages = false
    } else {
      throw APIError.offline
    }
    return await resolvePageDimensions(
      bookId: book.id,
      pages: storedPages,
      shouldRefreshCachedPages: shouldRefreshCachedPages
    )
  }

  func fetchSegmentPages(
    for book: Book,
    shouldEnsureOfflineReady: Bool,
    ensureOfflineReady: () async throws -> Void
  ) async -> [BookPage]? {
    let database = await DatabaseOperator.databaseIfConfigured()
    let fetchedPages: [BookPage]
    let shouldRefreshCachedPages: Bool

    if AppConfig.offlineFirstReading, shouldEnsureOfflineReady {
      do {
        try await ensureOfflineReady()
      } catch {
        logger.error("❌ Failed to prepare offline segment for book \(book.id): \(error)")
        return nil
      }

      guard let localPages = await database?.fetchPages(id: book.id) else {
        return nil
      }
      fetchedPages = localPages
      shouldRefreshCachedPages = false
    } else if let cachedPages = await database?.fetchPages(id: book.id) {
      fetchedPages = cachedPages
      shouldRefreshCachedPages = !AppConfig.offlineFirstReading && !AppConfig.isOffline
    } else {
      guard !AppConfig.isOffline else {
        return nil
      }

      do {
        fetchedPages = try await BookService.getBookPages(id: book.id)
        await database?.updateBookPages(bookId: book.id, pages: fetchedPages)
        shouldRefreshCachedPages = false
      } catch {
        logger.error("❌ Failed to preload segment pages for book \(book.id): \(error)")
        return nil
      }
    }

    return await resolvePageDimensions(
      bookId: book.id,
      pages: fetchedPages,
      shouldRefreshCachedPages: shouldRefreshCachedPages
    )
  }

  private func resolvePageDimensions(
    bookId: String,
    pages: [BookPage],
    shouldRefreshCachedPages: Bool
  ) async -> [BookPage] {
    var resolvedPages = pages

    if shouldRefreshCachedPages,
      resolvedPages.contains(where: { !$0.hasValidDimensions })
    {
      do {
        let refreshedPages = try await BookService.getBookPages(id: bookId)
        resolvedPages = preservingKnownDimensions(
          in: refreshedPages,
          from: resolvedPages
        )
        if let database = await DatabaseOperator.databaseIfConfigured() {
          await database.updateBookPages(bookId: bookId, pages: resolvedPages)
        }
      } catch {
        logger.warning(
          "⚠️ Failed to refresh page dimensions from server for book \(bookId): \(error)"
        )
      }
    }

    if resolvedPages.contains(where: { !$0.hasValidDimensions }) {
      resolvedPages = await OfflineManager.shared.fillMissingPageDimensions(
        instanceId: AppConfig.current.instanceId,
        bookId: bookId,
        pages: resolvedPages
      )
    }

    return resolvedPages
  }

  private func preservingKnownDimensions(
    in refreshedPages: [BookPage],
    from cachedPages: [BookPage]
  ) -> [BookPage] {
    let cachedDimensionsByFileName = cachedPages.reduce(into: [String: (width: Int, height: Int)]()) {
      result, page in
      guard page.hasValidDimensions, let width = page.width, let height = page.height else { return }
      result[page.fileName] = (width, height)
    }

    return refreshedPages.map { page in
      guard !page.hasValidDimensions,
        let dimensions = cachedDimensionsByFileName[page.fileName]
      else {
        return page
      }
      return page.withDimensions(width: dimensions.width, height: dimensions.height)
    }
  }

  func loadSoloPages(for bookId: String) async -> [Int] {
    let database = await DatabaseOperator.databaseIfConfigured()
    return await database?.fetchSoloPages(id: bookId) ?? []
  }

  func loadTableOfContents(for book: Book) async -> [ReaderTOCEntry] {
    let mediaProfile = book.media.mediaProfileValue ?? .unknown
    let database = await DatabaseOperator.databaseIfConfigured()

    if mediaProfile == .epub {
      if let localTOC = await database?.fetchTOC(id: book.id) {
        return localTOC
      }
      if !AppConfig.isOffline {
        do {
          let manifest = try await BookService.getBookManifest(id: book.id)
          let toc = await ReaderManifestService(bookId: book.id).parseTOC(manifest: manifest)
          await database?.updateBookTOC(bookId: book.id, toc: toc)
          return toc
        } catch {
          logger.error("❌ Failed to load TOC from manifest for book \(book.id): \(error)")
          return []
        }
      }
      return []
    }

    if mediaProfile == .pdf {
      return await database?.fetchTOC(id: book.id) ?? []
    }

    return []
  }

  func resolveAdjacentBooks(for bookId: String, readListId: String?) async -> (
    previous: Book?, next: Book?
  ) {
    let instanceId = AppConfig.current.instanceId
    let database = await DatabaseOperator.databaseIfConfigured()

    let resolvedNextBook = await resolveAdjacentBook(
      direction: .next,
      bookId: bookId,
      readListId: readListId,
      instanceId: instanceId,
      database: database
    )
    let resolvedPreviousBook = await resolveAdjacentBook(
      direction: .previous,
      bookId: bookId,
      readListId: readListId,
      instanceId: instanceId,
      database: database
    )

    return (resolvedPreviousBook, resolvedNextBook)
  }

  private enum AdjacentBookDirection {
    case previous
    case next
  }

  private func resolveAdjacentBook(
    direction: AdjacentBookDirection,
    bookId: String,
    readListId: String?,
    instanceId: String,
    database: DatabaseOperator?
  ) async -> Book? {
    if AppConfig.isOffline {
      return await cachedAdjacentBook(
        direction: direction,
        bookId: bookId,
        readListId: readListId,
        instanceId: instanceId,
        database: database
      )
    }

    do {
      let resolvedBook: Book?
      switch direction {
      case .previous:
        resolvedBook = try await BookService.getPreviousBook(
          bookId: bookId,
          readListId: readListId
        )
      case .next:
        resolvedBook = try await NextBookToReadResolver.resolve(
          after: bookId,
          readListId: readListId,
          instanceId: instanceId
        )
      }

      if let resolvedBook, let database {
        await database.upsertBook(dto: resolvedBook, instanceId: instanceId)
      }
      return resolvedBook
    } catch {
      logger.warning(
        "⚠️ Failed to resolve \(direction == .next ? "next" : "previous") book from server for \(bookId): \(error)"
      )
      return await cachedAdjacentBook(
        direction: direction,
        bookId: bookId,
        readListId: readListId,
        instanceId: instanceId,
        database: database
      )
    }
  }

  private func cachedAdjacentBook(
    direction: AdjacentBookDirection,
    bookId: String,
    readListId: String?,
    instanceId: String,
    database: DatabaseOperator?
  ) async -> Book? {
    switch direction {
    case .previous:
      return await database?.getPreviousBook(
        instanceId: instanceId,
        bookId: bookId,
        readListId: readListId
      )
    case .next:
      guard let database else { return nil }
      return await NextBookToReadResolver.resolveLocally(
        after: bookId,
        readListId: readListId,
        instanceId: instanceId,
        database: database
      )
    }
  }
}
