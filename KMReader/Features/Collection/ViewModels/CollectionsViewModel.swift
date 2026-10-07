//
// CollectionsViewModel.swift
//
//

import Foundation
import SwiftUI

@MainActor
@Observable
class CollectionsViewModel {
  var isLoading = false

  private(set) var pagination: PaginationState<IdentifiedString>
  private var pinnedIds: [String] = []
  private var serverPage = 0
  private var offlineIds: [String] = []
  private var offlineLoadKey: String?

  init(pageSize: Int = 50) {
    pagination = PaginationState<IdentifiedString>(pageSize: pageSize)
  }

  func loadCollections(
    libraryIds: [String]? = nil,
    searchText: String = "",
    sort: String? = nil,
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

    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else {
      guard loadID == pagination.loadID else { return }
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
        applyPage(ids: [], moreAvailable: false)
        return
      }
      let loadKey = "\(searchText)|\(sort ?? "")"
      if refresh || loadKey != offlineLoadKey {
        offlineIds = await database.fetchAllCollectionIds(
          instanceId: instanceId,
          searchText: searchText,
          sort: sort
        )
        offlineLoadKey = loadKey
      }
      let offset = pagination.currentPage * pagination.pageSize
      let pageIds = Array(offlineIds.dropFirst(offset).prefix(pagination.pageSize))
      guard loadID == pagination.loadID else { return }
      applyPage(ids: pageIds, moreAvailable: offset + pageIds.count < offlineIds.count)
    } else {
      if refresh {
        serverPage = 0
        if let database = try? await DatabaseOperator.database() {
          let pinned = await database.fetchPinnedCollectionIds(
            instanceId: instanceId,
            searchText: searchText,
            sort: sort
          )
          guard loadID == pagination.loadID else { return }
          pinnedIds = pinned
        }
      }
      do {
        let (ids, moreAvailable) = try await fetchServerCollectionPage(
          libraryIds: libraryIds,
          searchText: searchText,
          sort: sort,
          pinnedSet: Set(pinnedIds)
        )

        guard loadID == pagination.loadID else { return }
        if pagination.currentPage == 0 {
          applyPage(ids: pinnedIds + ids, moreAvailable: moreAvailable)
        } else {
          applyPage(ids: ids, moreAvailable: moreAvailable)
        }
      } catch {
        guard loadID == pagination.loadID else { return }
        if refresh {
          ErrorManager.shared.alert(error: error)
        } else {
          pagination.hasMorePages = false
        }
      }
    }
  }

  private func fetchServerCollectionPage(
    libraryIds: [String]?,
    searchText: String,
    sort: String?,
    pinnedSet: Set<String>
  ) async throws -> (ids: [String], moreAvailable: Bool) {
    var page = try await SyncService.syncCollections(
      libraryIds: libraryIds,
      page: serverPage,
      size: pagination.pageSize,
      sort: sort,
      search: searchText.isEmpty ? nil : searchText
    )
    serverPage += 1
    var ids = page.content.map { $0.id }.filter { !pinnedSet.contains($0) }
    while ids.isEmpty && !page.last {
      page = try await SyncService.syncCollections(
        libraryIds: libraryIds,
        page: serverPage,
        size: pagination.pageSize,
        sort: sort,
        search: searchText.isEmpty ? nil : searchText
      )
      serverPage += 1
      ids = page.content.map { $0.id }.filter { !pinnedSet.contains($0) }
    }
    return (ids, !page.last)
  }

  private func applyPage(ids: [String], moreAvailable: Bool) {
    withAnimation {
      _ = pagination.applyPage(ids.map(IdentifiedString.init))
    }
    pagination.advance(moreAvailable: moreAvailable)
  }

  func removeCollection(id: String) {
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
