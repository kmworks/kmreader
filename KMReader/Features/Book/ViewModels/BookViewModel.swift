//
// BookViewModel.swift
//
//

import Foundation
import SwiftUI

@MainActor
@Observable
class BookViewModel {
  var currentBook: Book?
  var isLoading = false

  private(set) var pagination = PaginationState<IdentifiedString>(pageSize: 50)

  private var lastBrowseQuery:
    (
      browseOpts: BookBrowseOptions,
      searchText: String,
      libraryIds: [String]?,
      useLocalOnly: Bool,
      offlineOnly: Bool
    )?

  func loadSeriesBooks(
    seriesId: String,
    browseOpts: BookBrowseOptions,
    refresh: Bool = true
  ) async {
    guard let loadID = beginLoad(refresh: refresh) else { return }

    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    if AppConfig.isOffline {
      guard let database = try? await DatabaseOperator.database() else {
        guard loadID == pagination.loadID else { return }
        applyPage(ids: [], moreAvailable: false)
        return
      }
      let ids = await database.fetchSeriesBookIds(
        seriesId: seriesId,
        browseOpts: browseOpts,
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      guard loadID == pagination.loadID else { return }
      applyPage(ids: ids, moreAvailable: ids.count == pagination.pageSize)
    } else {
      do {
        let page = try await SyncService.syncBooks(
          seriesId: seriesId,
          page: pagination.currentPage,
          size: pagination.pageSize,
          browseOpts: normalizedRemoteBrowseOptions(browseOpts)
        )

        guard loadID == pagination.loadID else { return }
        let ids = page.content.map { $0.id }
        applyPage(ids: ids, moreAvailable: !page.last)
      } catch {
        guard loadID == pagination.loadID else { return }
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  /// Re-fetches the already-loaded page window in place, preserving scroll
  /// position. Used for projection-change-driven refreshes; explicit user
  /// actions (pull-to-refresh, filter changes) still use a full refresh.
  func revalidateSeriesBooks(
    seriesId: String,
    browseOpts: BookBrowseOptions
  ) async {
    await revalidateWindow(
      fetchWindow: { windowSize in
        if AppConfig.isOffline {
          guard let database = try? await DatabaseOperator.database() else { return nil }
          let ids = await database.fetchSeriesBookIds(
            seriesId: seriesId,
            browseOpts: browseOpts,
            page: 0,
            size: windowSize
          )
          return (ids, ids.count == windowSize)
        }
        do {
          let page = try await SyncService.syncBooks(
            seriesId: seriesId,
            page: 0,
            size: windowSize,
            browseOpts: normalizedRemoteBrowseOptions(browseOpts)
          )
          return (page.content.map { $0.id }, !page.last)
        } catch {
          return nil
        }
      },
      refreshFallback: {
        await loadSeriesBooks(seriesId: seriesId, browseOpts: browseOpts, refresh: true)
      }
    )
  }

  private func applyPage(ids: [String], moreAvailable: Bool) {
    let wrappedIds = ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.applyPage(wrappedIds)
    }
    pagination.advance(moreAvailable: moreAvailable)
  }

  func removeBook(id: String) {
    withAnimation {
      _ = pagination.removeItems(withIDs: [id])
    }
  }

  /// Shared windowing for revalidation: re-fetches pages 0..<currentPage as a
  /// single window and replaces the loaded items in place, keeping currentPage
  /// and loadID so scroll position and item identity survive the update.
  private func revalidateWindow(
    fetchWindow: (Int) async -> (ids: [String], moreAvailable: Bool)?,
    refreshFallback: () async -> Void
  ) async {
    guard !isLoading else { return }
    let windowSize = pagination.currentPage * pagination.pageSize
    guard windowSize > 0 else {
      await refreshFallback()
      return
    }

    let loadID = pagination.loadID
    withAnimation {
      isLoading = true
    }
    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    guard let result = await fetchWindow(windowSize) else { return }
    guard loadID == pagination.loadID else { return }
    let wrappedIds = result.ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.replaceItems(wrappedIds, moreAvailable: result.moreAvailable)
    }
  }

  private func beginLoad(refresh: Bool) -> UUID? {
    if refresh {
      withAnimation {
        pagination.reset()
        isLoading = true
      }
      return pagination.loadID
    }

    guard pagination.hasMorePages && !isLoading else { return nil }
    withAnimation {
      isLoading = true
    }
    return pagination.loadID
  }

  func updatePageReadProgress(bookId: String, page: Int, completed: Bool = false) async {
    do {
      try await BookService.updatePageReadProgress(
        bookId: bookId,
        page: page,
        completed: completed
      )
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  func markAsRead(bookId: String) async {
    do {
      try await BookService.markAsRead(bookId: bookId)
      let updatedBook = try await SyncService.syncBook(bookId: bookId)
      _ = try? await SyncService.syncSeriesDetail(seriesId: updatedBook.seriesId)
      if currentBook?.id == bookId {
        currentBook = updatedBook
      }
      await ContentProjectionNotifier.postBookAndSeriesDidChange(
        bookId: bookId,
        seriesId: updatedBook.seriesId,
        reason: .readingProgress
      )
      await postReadStatusDashboardRefresh()
      ErrorManager.shared.notify(message: String(localized: "notification.book.markedRead"))
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  func markAsUnread(bookId: String) async {
    do {
      try await BookService.markAsUnread(bookId: bookId)
      let updatedBook = try await SyncService.syncBook(bookId: bookId)
      _ = try? await SyncService.syncSeriesDetail(seriesId: updatedBook.seriesId)
      if currentBook?.id == bookId {
        currentBook = updatedBook
      }
      await ContentProjectionNotifier.postBookAndSeriesDidChange(
        bookId: bookId,
        seriesId: updatedBook.seriesId,
        reason: .readingProgress
      )
      await postReadStatusDashboardRefresh()
      ErrorManager.shared.notify(message: String(localized: "notification.book.markedUnread"))
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  func loadBrowseBooks(
    browseOpts: BookBrowseOptions,
    searchText: String = "",
    libraryIds: [String]? = nil,
    refresh: Bool = false,
    useLocalOnly: Bool = false,
    offlineOnly: Bool = false
  ) async {
    guard let loadID = beginLoad(refresh: refresh) else { return }
    lastBrowseQuery = (browseOpts, searchText, libraryIds, useLocalOnly, offlineOnly)

    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    if AppConfig.isOffline || useLocalOnly {
      guard let database = try? await DatabaseOperator.database() else {
        guard loadID == pagination.loadID else { return }
        applyPage(ids: [], moreAvailable: false)
        return
      }
      let ids = await database.fetchBrowseBookIds(
        instanceId: AppConfig.current.instanceId,
        libraryIds: libraryIds,
        searchText: searchText,
        browseOpts: browseOpts,
        offset: pagination.currentPage * pagination.pageSize,
        limit: pagination.pageSize,
        offlineOnly: offlineOnly
      )
      guard loadID == pagination.loadID else { return }
      applyPage(ids: ids, moreAvailable: ids.count == pagination.pageSize)
    } else {
      do {
        let page = try await SyncService.syncBrowseBooks(
          libraryIds: libraryIds,
          page: pagination.currentPage,
          size: pagination.pageSize,
          searchTerm: searchText.isEmpty ? nil : searchText,
          browseOpts: normalizedRemoteBrowseOptions(browseOpts)
        )

        guard loadID == pagination.loadID else { return }
        let ids = page.content.map { $0.id }
        applyPage(ids: ids, moreAvailable: !page.last)
      } catch {
        guard loadID == pagination.loadID else { return }
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func normalizedRemoteBrowseOptions(_ browseOpts: BookBrowseOptions)
    -> BookBrowseOptions
  {
    guard browseOpts.sortField == .downloadDate else {
      return browseOpts
    }

    var fallback = browseOpts
    fallback.sortField = .dateAdded
    return fallback
  }

  /// Re-runs the current browse query from the first page. No-op before the
  /// first load; lets pull-to-refresh await the reload without knowing the
  /// query owned by the presenting view.
  func refreshBrowse() async {
    guard let query = lastBrowseQuery else { return }
    await loadBrowseBooks(
      browseOpts: query.browseOpts,
      searchText: query.searchText,
      libraryIds: query.libraryIds,
      refresh: true,
      useLocalOnly: query.useLocalOnly,
      offlineOnly: query.offlineOnly
    )
  }

  private func postReadStatusDashboardRefresh() async {
    await DashboardSectionRefreshNotifier.postReadStatusChanged(
      source: .manual,
      reason: "Book read status changed"
    )
  }

  func loadReadListBooks(
    readListId: String,
    browseOpts: ReadListBookBrowseOptions,
    libraryIds: [String]? = nil,
    refresh: Bool = false
  ) async {
    guard let loadID = beginLoad(refresh: refresh) else { return }

    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    if AppConfig.isOffline {
      guard let database = try? await DatabaseOperator.database() else {
        guard loadID == pagination.loadID else { return }
        applyPage(ids: [], moreAvailable: false)
        return
      }
      let ids = await database.fetchReadListBookIds(
        readListId: readListId,
        browseOpts: browseOpts,
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      guard loadID == pagination.loadID else { return }
      applyPage(ids: ids, moreAvailable: ids.count == pagination.pageSize)
    } else {
      do {
        let page = try await SyncService.syncReadListBooks(
          readListId: readListId,
          page: pagination.currentPage,
          size: pagination.pageSize,
          browseOpts: browseOpts,
          libraryIds: libraryIds
        )

        guard loadID == pagination.loadID else { return }
        let ids = page.content.map { $0.id }
        applyPage(ids: ids, moreAvailable: !page.last)
      } catch {
        guard loadID == pagination.loadID else { return }
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  /// Re-fetches the already-loaded page window in place, preserving scroll
  /// position. See `revalidateSeriesBooks`.
  func revalidateReadListBooks(
    readListId: String,
    browseOpts: ReadListBookBrowseOptions,
    libraryIds: [String]? = nil
  ) async {
    await revalidateWindow(
      fetchWindow: { windowSize in
        if AppConfig.isOffline {
          guard let database = try? await DatabaseOperator.database() else { return nil }
          let ids = await database.fetchReadListBookIds(
            readListId: readListId,
            browseOpts: browseOpts,
            page: 0,
            size: windowSize
          )
          return (ids, ids.count == windowSize)
        }
        do {
          let page = try await SyncService.syncReadListBooks(
            readListId: readListId,
            page: 0,
            size: windowSize,
            browseOpts: browseOpts,
            libraryIds: libraryIds
          )
          return (page.content.map { $0.id }, !page.last)
        } catch {
          return nil
        }
      },
      refreshFallback: {
        await loadReadListBooks(
          readListId: readListId,
          browseOpts: browseOpts,
          libraryIds: libraryIds,
          refresh: true
        )
      }
    )
  }

  func loadSmartListBooks(
    smartListId: String,
    browseOpts: BookBrowseOptions,
    refresh: Bool = false
  ) async {
    guard let loadID = beginLoad(refresh: refresh) else { return }

    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    // Smart lists are evaluated server-side; offline there is nothing to show.
    if AppConfig.isOffline {
      guard loadID == pagination.loadID else { return }
      applyPage(ids: [], moreAvailable: false)
      return
    }

    do {
      let remoteOpts = normalizedRemoteBrowseOptions(browseOpts)
      let search = BookSearch(
        condition: BookSearch.buildCondition(filters: remoteOpts.toSearchFilters()))
      let page = try await SyncService.syncSmartListBooks(
        smartListId: smartListId,
        page: pagination.currentPage,
        size: pagination.pageSize,
        search: search,
        sort: remoteOpts.sortQueryValues
      )

      guard loadID == pagination.loadID else { return }
      let ids = page.content.map { $0.id }
      applyPage(ids: ids, moreAvailable: !page.last)
    } catch {
      guard loadID == pagination.loadID else { return }
      ErrorManager.shared.alert(error: error)
    }
  }

  /// Re-fetches the already-loaded page window in place, preserving scroll
  /// position. See `revalidateSeriesBooks`.
  func revalidateSmartListBooks(
    smartListId: String,
    browseOpts: BookBrowseOptions
  ) async {
    await revalidateWindow(
      fetchWindow: { windowSize in
        guard !AppConfig.isOffline else { return nil }
        do {
          let remoteOpts = normalizedRemoteBrowseOptions(browseOpts)
          let search = BookSearch(
            condition: BookSearch.buildCondition(filters: remoteOpts.toSearchFilters()))
          let page = try await SyncService.syncSmartListBooks(
            smartListId: smartListId,
            page: 0,
            size: windowSize,
            search: search,
            sort: remoteOpts.sortQueryValues
          )
          return (page.content.map { $0.id }, !page.last)
        } catch {
          return nil
        }
      },
      refreshFallback: {
        await loadSmartListBooks(smartListId: smartListId, browseOpts: browseOpts, refresh: true)
      }
    )
  }
}
