//
// SeriesViewModel.swift
//
//

import Foundation
import SwiftUI

@MainActor
@Observable
class SeriesViewModel {
  var isLoading = false

  private(set) var pagination = PaginationState<IdentifiedString>(pageSize: 50)

  private var lastBrowseQuery:
    (
      browseOpts: SeriesBrowseOptions,
      searchText: String,
      libraryIds: [String]?,
      useLocalOnly: Bool,
      offlineOnly: Bool
    )?

  func loadSeries(
    browseOpts: SeriesBrowseOptions,
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
      let ids = await database.fetchBrowseSeriesIds(
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
        let page = try await SyncService.syncSeriesPage(
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
        if refresh {
          ErrorManager.shared.alert(error: error)
        }
      }
    }
  }

  /// Re-runs the current browse query from the first page. No-op before the
  /// first load; lets pull-to-refresh await the reload without knowing the
  /// query owned by the presenting view.
  func refreshBrowse() async {
    guard let query = lastBrowseQuery else { return }
    await loadSeries(
      browseOpts: query.browseOpts,
      searchText: query.searchText,
      libraryIds: query.libraryIds,
      refresh: true,
      useLocalOnly: query.useLocalOnly,
      offlineOnly: query.offlineOnly
    )
  }

  private func normalizedRemoteBrowseOptions(_ browseOpts: SeriesBrowseOptions)
    -> SeriesBrowseOptions
  {
    guard browseOpts.sortField == .downloadDate else {
      return browseOpts
    }

    var fallback = browseOpts
    fallback.sortField = .dateAdded
    return fallback
  }

  func loadCollectionSeries(
    collectionId: String,
    browseOpts: CollectionSeriesBrowseOptions,
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
      let ids = await database.fetchCollectionSeriesIds(
        collectionId: collectionId,
        browseOpts: browseOpts,
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      guard loadID == pagination.loadID else { return }
      applyPage(ids: ids, moreAvailable: ids.count == pagination.pageSize)
    } else {
      do {
        let page = try await SyncService.syncCollectionSeries(
          collectionId: collectionId,
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

  private func applyPage(ids: [String], moreAvailable: Bool) {
    let wrappedIds = ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.applyPage(wrappedIds)
    }
    pagination.advance(moreAvailable: moreAvailable)
  }

  func loadSmartListSeries(
    smartListId: String,
    browseOpts: SeriesBrowseOptions,
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
      let search = SeriesSearch(
        condition: SeriesSearch.buildCondition(filters: remoteOpts.toSearchFilters()))
      let page = try await SyncService.syncSmartListSeries(
        smartListId: smartListId,
        page: pagination.currentPage,
        size: pagination.pageSize,
        search: search,
        sort: [remoteOpts.sortString]
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
  /// position. Used for projection-change-driven refreshes; explicit user
  /// actions (filter changes) still use a full refresh.
  func revalidateCollectionSeries(
    collectionId: String,
    browseOpts: CollectionSeriesBrowseOptions,
    libraryIds: [String]? = nil
  ) async {
    guard !isLoading else { return }
    let windowSize = pagination.currentPage * pagination.pageSize
    guard windowSize > 0 else {
      await loadCollectionSeries(
        collectionId: collectionId,
        browseOpts: browseOpts,
        libraryIds: libraryIds,
        refresh: true
      )
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

    let result: (ids: [String], moreAvailable: Bool)?
    if AppConfig.isOffline {
      guard let database = try? await DatabaseOperator.database() else { return }
      let ids = await database.fetchCollectionSeriesIds(
        collectionId: collectionId,
        browseOpts: browseOpts,
        page: 0,
        size: windowSize
      )
      result = (ids, ids.count == windowSize)
    } else {
      do {
        let page = try await SyncService.syncCollectionSeries(
          collectionId: collectionId,
          page: 0,
          size: windowSize,
          browseOpts: browseOpts,
          libraryIds: libraryIds
        )
        result = (page.content.map { $0.id }, !page.last)
      } catch {
        return
      }
    }

    guard loadID == pagination.loadID, let result else { return }
    let wrappedIds = result.ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.replaceItems(wrappedIds, moreAvailable: result.moreAvailable)
    }
  }

  /// Re-fetches the already-loaded page window in place, preserving scroll
  /// position. See `revalidateCollectionSeries`.
  func revalidateSmartListSeries(
    smartListId: String,
    browseOpts: SeriesBrowseOptions
  ) async {
    guard !isLoading else { return }
    let windowSize = pagination.currentPage * pagination.pageSize
    guard windowSize > 0 else {
      await loadSmartListSeries(smartListId: smartListId, browseOpts: browseOpts, refresh: true)
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

    guard !AppConfig.isOffline else { return }

    let result: (ids: [String], moreAvailable: Bool)?
    do {
      let remoteOpts = normalizedRemoteBrowseOptions(browseOpts)
      let search = SeriesSearch(
        condition: SeriesSearch.buildCondition(filters: remoteOpts.toSearchFilters()))
      let page = try await SyncService.syncSmartListSeries(
        smartListId: smartListId,
        page: 0,
        size: windowSize,
        search: search,
        sort: [remoteOpts.sortString]
      )
      result = (page.content.map { $0.id }, !page.last)
    } catch {
      return
    }

    guard loadID == pagination.loadID, let result else { return }
    let wrappedIds = result.ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.replaceItems(wrappedIds, moreAvailable: result.moreAvailable)
    }
  }

  func removeSeries(id: String) {
    withAnimation {
      _ = pagination.removeItems(withIDs: [id])
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
}
