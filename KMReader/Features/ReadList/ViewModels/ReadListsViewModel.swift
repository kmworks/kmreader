//
// ReadListsViewModel.swift
//
//

import Foundation
import SwiftUI

@MainActor
@Observable
class ReadListsViewModel {
  var isLoading = false
  private(set) var totalCount: Int?
  private(set) var loadError: Error?

  private(set) var pagination: PaginationState<IdentifiedString>
  private var pinnedIds: [String] = []
  private var serverPage = 0
  private var offlineIds: [String] = []
  private var offlineLoadKey: String?

  init(pageSize: Int = 50) {
    pagination = PaginationState<IdentifiedString>(pageSize: pageSize)
  }

  func loadReadLists(
    libraryIds: [String]? = nil,
    searchText: String = "",
    sort: String? = nil,
    refresh: Bool = false,
    reportsErrors: Bool = true,
    syncAutomaticBooks: Bool = true
  ) async {
    guard let loadID = beginLoad(refresh: refresh) else { return }

    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else {
      guard loadID == pagination.loadID else { return }
      totalCount = 0
      applyPage(ids: [], moreAvailable: false)
      return
    }

    if refresh {
      offlineIds = []
      offlineLoadKey = nil
    }

    if AppConfig.isOffline {
      guard let database = try? await DatabaseOperator.database() else {
        guard loadID == pagination.loadID else { return }
        totalCount = 0
        applyPage(ids: [], moreAvailable: false)
        return
      }
      let loadKey = "\(searchText)|\(sort ?? "")"
      if refresh || loadKey != offlineLoadKey {
        offlineIds = await database.fetchAllReadListIds(
          instanceId: instanceId,
          searchText: searchText,
          sort: sort
        )
        offlineLoadKey = loadKey
      }
      let offset = pagination.currentPage * pagination.pageSize
      let pageIds = Array(offlineIds.dropFirst(offset).prefix(pagination.pageSize))
      guard loadID == pagination.loadID else { return }
      totalCount = offlineIds.count
      applyPage(ids: pageIds, moreAvailable: offset + pageIds.count < offlineIds.count)
    } else {
      if refresh {
        serverPage = 0
        if let database = try? await DatabaseOperator.database() {
          let pinned = await database.fetchPinnedReadListIds(
            instanceId: instanceId,
            searchText: searchText,
            sort: sort
          )
          guard loadID == pagination.loadID else { return }
          pinnedIds = pinned
        }
      }
      do {
        let result = try await fetchServerReadListPage(
          libraryIds: libraryIds,
          searchText: searchText,
          sort: sort,
          pinnedSet: Set(pinnedIds),
          syncAutomaticBooks: syncAutomaticBooks
        )

        guard loadID == pagination.loadID else { return }
        totalCount = result.totalElements
        if pagination.currentPage == 0 {
          applyPage(ids: pinnedIds + result.ids, moreAvailable: result.moreAvailable)
        } else {
          applyPage(ids: result.ids, moreAvailable: result.moreAvailable)
        }
      } catch {
        guard loadID == pagination.loadID else { return }
        if ErrorManager.shared.shouldShowError(error) {
          loadError = error
        }
        if refresh {
          if reportsErrors {
            ErrorManager.shared.alert(error: error)
          }
        } else {
          pagination.hasMorePages = false
        }
      }
    }
  }

  private func fetchServerReadListPage(
    libraryIds: [String]?,
    searchText: String,
    sort: String?,
    pinnedSet: Set<String>,
    syncAutomaticBooks: Bool
  ) async throws -> (ids: [String], moreAvailable: Bool, totalElements: Int) {
    var page = try await SyncService.syncReadLists(
      libraryIds: libraryIds,
      page: serverPage,
      size: pagination.pageSize,
      sort: sort,
      search: searchText.isEmpty ? nil : searchText,
      syncAutomaticBooks: syncAutomaticBooks
    )
    let totalElements = page.totalElements
    serverPage += 1
    var ids = page.content.map { $0.id }.filter { !pinnedSet.contains($0) }
    while ids.isEmpty && !page.last {
      page = try await SyncService.syncReadLists(
        libraryIds: libraryIds,
        page: serverPage,
        size: pagination.pageSize,
        sort: sort,
        search: searchText.isEmpty ? nil : searchText,
        syncAutomaticBooks: syncAutomaticBooks
      )
      serverPage += 1
      ids = page.content.map { $0.id }.filter { !pinnedSet.contains($0) }
    }
    return (ids, !page.last, totalElements)
  }

  private func applyPage(ids: [String], moreAvailable: Bool) {
    withAnimation {
      _ = pagination.applyPage(ids.map(IdentifiedString.init))
    }
    pagination.advance(moreAvailable: moreAvailable)
  }

  func removeReadList(id: String) {
    withAnimation {
      if pagination.removeItems(withIDs: [id]), let count = totalCount {
        totalCount = max(0, count - 1)
      }
    }
  }

  private func beginLoad(refresh: Bool) -> UUID? {
    if refresh {
      totalCount = nil
      loadError = nil
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
