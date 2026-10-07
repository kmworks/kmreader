//
// DashboardSectionViewModel.swift
//
//

import Foundation
import SwiftUI

/// Loads one dashboard row.
///
/// Loads run in tasks this model owns rather than in the view's `.task`:
/// switching the split view's sidebar back to Home adds, removes, and re-adds
/// the dashboard within a few milliseconds, which cancels view-scoped tasks
/// mid-request while the view keeps its state. A load is only started on
/// appear when none has completed or is running, and the newest request wins:
/// a reload supersedes a load in flight instead of being dropped by it.
@MainActor
@Observable
final class DashboardSectionViewModel {
  let section: DashboardSection

  private(set) var pagination = PaginationState<IdentifiedString>(pageSize: 20)

  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var hasLoadedFirstPage = false
  @ObservationIgnored private var didSeedFromCache = false
  @ObservationIgnored private let sectionCacheStore = DashboardSectionCacheStore.shared

  init(section: DashboardSection) {
    self.section = section
  }

  /// Loads the first page unless a load already completed or is running.
  func ensureLoaded(libraryIds: [String]) {
    guard !hasLoadedFirstPage, loadTask == nil else { return }
    startReload(libraryIds: libraryIds)
  }

  /// Reloads from the first page, returning once the newest load settles.
  func reload(libraryIds: [String]) async {
    startReload(libraryIds: libraryIds)
    while let loadTask {
      await loadTask.value
    }
  }

  func loadMoreIfNeeded(after item: IdentifiedString, libraryIds: [String]) {
    guard loadTask == nil, pagination.hasMorePages, pagination.shouldLoadMore(after: item) else { return }
    startLoad(libraryIds: libraryIds)
  }

  func removeItem(id: String) {
    withAnimation {
      _ = pagination.removeItems(withIDs: [id])
    }
  }

  /// Restarts from the first page; loaded items stay on screen until it lands.
  private func startReload(libraryIds: [String]) {
    loadTask?.cancel()
    loadTask = nil
    withAnimation {
      pagination.reset()
    }
    startLoad(libraryIds: libraryIds)
  }

  private func startLoad(libraryIds: [String]) {
    let loadID = pagination.loadID
    loadTask = Task {
      await loadPage(loadID: loadID, libraryIds: libraryIds)
      // A reload that superseded this load owns `loadTask` now.
      if loadID == pagination.loadID {
        loadTask = nil
      }
    }
  }

  private func loadPage(loadID: UUID, libraryIds: [String]) async {
    let instanceId = AppConfig.current.instanceId
    let page = pagination.currentPage
    let pageSize = pagination.pageSize
    let isFirstPage = page == 0

    if isFirstPage, !AppConfig.isOffline {
      seedFromCacheIfNeeded()
    }

    if AppConfig.isOffline {
      let ids: [String]
      switch section.contentKind {
      case .books:
        ids = await section.fetchOfflineBookIds(
          libraryIds: libraryIds,
          offset: page * pageSize,
          limit: pageSize
        )
      case .series:
        ids = await section.fetchOfflineSeriesIds(
          libraryIds: libraryIds,
          offset: page * pageSize,
          limit: pageSize
        )
      }
      guard loadID == pagination.loadID else { return }
      applyPage(ids: ids, moreAvailable: ids.count == pageSize)
      updateWidgetDataIfNeeded(
        ids: ids,
        isFirstPage: isFirstPage,
        instanceId: instanceId,
        libraryIds: libraryIds
      )
      return
    }

    do {
      switch section.contentKind {
      case .books:
        guard
          let result = try await section.fetchBooks(libraryIds: libraryIds, page: page, size: pageSize),
          loadID == pagination.loadID
        else { return }
        let ids = result.content.map(\.id)
        if isFirstPage {
          _ = sectionCacheStore.updateIfChanged(section: section, ids: ids)
          section.widgetDataTarget?.update(books: result.content, instanceId: instanceId, libraryIds: libraryIds)
        }
        applyPage(ids: ids, moreAvailable: !result.last)
      case .series:
        guard
          let result = try await section.fetchSeries(libraryIds: libraryIds, page: page, size: pageSize),
          loadID == pagination.loadID
        else { return }
        let ids = result.content.map(\.id)
        if isFirstPage {
          _ = sectionCacheStore.updateIfChanged(section: section, ids: ids)
          section.widgetDataTarget?.update(series: result.content, instanceId: instanceId, libraryIds: libraryIds)
        }
        applyPage(ids: ids, moreAvailable: !result.last)
      }
    } catch {
      // A superseded load was cancelled on purpose; only the newest reports.
      guard loadID == pagination.loadID else { return }
      ErrorManager.shared.alert(error: error)
    }
  }

  private func seedFromCacheIfNeeded() {
    guard !didSeedFromCache, pagination.isEmpty else { return }
    didSeedFromCache = true

    let cachedIds = sectionCacheStore.ids(for: section)
    guard !cachedIds.isEmpty else { return }
    withAnimation {
      pagination.items = cachedIds.map(IdentifiedString.init)
    }
  }

  private func applyPage(ids: [String], moreAvailable: Bool) {
    if pagination.currentPage == 0 {
      hasLoadedFirstPage = true
    }
    withAnimation {
      _ = pagination.applyPage(ids.map(IdentifiedString.init))
    }
    pagination.advance(moreAvailable: moreAvailable)
  }

  private func updateWidgetDataIfNeeded(
    ids: [String],
    isFirstPage: Bool,
    instanceId: String,
    libraryIds: [String]
  ) {
    guard isFirstPage, let target = section.widgetDataTarget else { return }
    guard !instanceId.isEmpty else { return }

    Task {
      await target.update(ids: ids, instanceId: instanceId, libraryIds: libraryIds)
    }
  }
}
