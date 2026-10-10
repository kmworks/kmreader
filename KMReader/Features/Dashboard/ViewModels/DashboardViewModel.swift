//
// DashboardViewModel.swift
//
//

import Foundation
import SwiftUI

/// Loads every dashboard row.
///
/// Loads run in tasks this model owns rather than in any view's `.task`:
/// switching the split view's sidebar back to Home adds, removes, and re-adds
/// the dashboard within a few milliseconds, which cancels view-scoped tasks
/// mid-request while the view keeps its state. A load is only started for a
/// section when none has completed or is running, and the newest request wins:
/// a reload supersedes a load in flight instead of being dropped by it.
@MainActor
@Observable
final class DashboardViewModel {
  private struct SectionState {
    var pagination = PaginationState<IdentifiedString>(pageSize: 20)
    var hasLoadedFirstPage = false
    var didSeedFromCache = false
  }

  private var sectionStates: [DashboardSection: SectionState] = [:]

  @ObservationIgnored private var loadTasks: [DashboardSection: Task<Void, Never>] = [:]
  @ObservationIgnored private let sectionCacheStore = DashboardSectionCacheStore.shared

  func items(for section: DashboardSection) -> [IdentifiedString] {
    sectionStates[section]?.pagination.items ?? []
  }

  func isEmpty(for section: DashboardSection) -> Bool {
    sectionStates[section]?.pagination.isEmpty ?? true
  }

  /// Starts the first load for every section that has neither completed nor
  /// started one.
  func ensureLoaded(sections: [DashboardSection], libraryIds: [String]) {
    for section in sections where section != .readListsInProgress {
      let loaded = sectionStates[section]?.hasLoadedFirstPage ?? false
      guard !loaded, loadTasks[section] == nil else { continue }
      startReload(section: section, libraryIds: libraryIds)
    }
  }

  /// Reloads the given sections from the first page, returning once every
  /// newest load settles.
  func reload(
    sections: [DashboardSection],
    libraryIds: [String],
    source: DashboardRefreshSource = .manual
  ) async {
    // DashboardRefreshSource's Equatable is MainActor-isolated; compare
    // before the concurrent group tasks.
    let syncReadListsFromRemote = source == .manual
    await withTaskGroup(of: Void.self) { group in
      for section in sections {
        if section == .readListsInProgress {
          group.addTask {
            // A manual refresh also pulls other devices' changes; other
            // reloads only re-derive from local data.
            if syncReadListsFromRemote {
              await ReadListReadingService.shared.sync(instanceId: AppConfig.current.instanceId)
            } else {
              await ReadListReadingService.shared.refreshSnapshot()
            }
          }
        } else {
          group.addTask {
            await self.reloadSection(section, libraryIds: libraryIds)
          }
        }
      }
    }
  }

  /// Applies a posted reload command to the rendered sections it names.
  func applyReloadCommand(
    _ command: DashboardSectionReloadCommand,
    sections: [DashboardSection],
    libraryIds: [String]
  ) async {
    await reload(
      sections: sections.filter { command.includes($0) },
      libraryIds: libraryIds,
      source: command.source
    )
  }

  func removeItem(section: DashboardSection, id: String) {
    withAnimation {
      _ = sectionStates[section]?.pagination.removeItems(withIDs: [id])
    }
  }

  private func reloadSection(_ section: DashboardSection, libraryIds: [String]) async {
    startReload(section: section, libraryIds: libraryIds)
    // A superseding reload owns the task slot now; await the newest.
    while let task = loadTasks[section] {
      await task.value
    }
  }

  /// Restarts from the first page; loaded items stay on screen until it lands.
  private func startReload(section: DashboardSection, libraryIds: [String]) {
    loadTasks[section]?.cancel()
    loadTasks[section] = nil
    withAnimation {
      sectionStates[section, default: SectionState()].pagination.reset()
    }
    guard let loadID = sectionStates[section]?.pagination.loadID else { return }
    startLoad(section: section, loadID: loadID, libraryIds: libraryIds)
  }

  private func startLoad(section: DashboardSection, loadID: UUID, libraryIds: [String]) {
    loadTasks[section] = Task {
      await loadPage(section: section, loadID: loadID, libraryIds: libraryIds)
      // A reload that superseded this load owns the task slot now.
      if loadID == sectionStates[section]?.pagination.loadID {
        loadTasks[section] = nil
      }
    }
  }

  private func loadPage(section: DashboardSection, loadID: UUID, libraryIds: [String]) async {
    let instanceId = AppConfig.current.instanceId
    let state = sectionStates[section] ?? SectionState()
    let page = state.pagination.currentPage
    let pageSize = state.pagination.pageSize
    let isFirstPage = page == 0

    if isFirstPage, !AppConfig.isOffline {
      seedFromCacheIfNeeded(section: section)
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
      guard loadID == sectionStates[section]?.pagination.loadID else { return }
      applyPage(section: section, ids: ids, moreAvailable: ids.count == pageSize)
      updateWidgetDataIfNeeded(
        section: section,
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
          loadID == sectionStates[section]?.pagination.loadID
        else { return }
        let ids = result.content.map(\.id)
        if isFirstPage {
          _ = sectionCacheStore.updateIfChanged(section: section, ids: ids)
          section.widgetDataTarget?.update(books: result.content, instanceId: instanceId, libraryIds: libraryIds)
        }
        applyPage(section: section, ids: ids, moreAvailable: !result.last)
      case .series:
        guard
          let result = try await section.fetchSeries(libraryIds: libraryIds, page: page, size: pageSize),
          loadID == sectionStates[section]?.pagination.loadID
        else { return }
        let ids = result.content.map(\.id)
        if isFirstPage {
          _ = sectionCacheStore.updateIfChanged(section: section, ids: ids)
          section.widgetDataTarget?.update(series: result.content, instanceId: instanceId, libraryIds: libraryIds)
        }
        applyPage(section: section, ids: ids, moreAvailable: !result.last)
      }
    } catch {
      // A superseded load was cancelled on purpose; only the newest reports.
      guard loadID == sectionStates[section]?.pagination.loadID else { return }
      ErrorManager.shared.alert(error: error)
    }
  }

  private func seedFromCacheIfNeeded(section: DashboardSection) {
    var state = sectionStates[section] ?? SectionState()
    guard !state.didSeedFromCache, state.pagination.isEmpty else { return }
    state.didSeedFromCache = true

    let cachedIds = sectionCacheStore.ids(for: section)
    guard !cachedIds.isEmpty else {
      sectionStates[section] = state
      return
    }
    withAnimation {
      state.pagination.items = cachedIds.map(IdentifiedString.init)
      sectionStates[section] = state
    }
  }

  private func applyPage(section: DashboardSection, ids: [String], moreAvailable: Bool) {
    var state = sectionStates[section] ?? SectionState()
    if state.pagination.currentPage == 0 {
      state.hasLoadedFirstPage = true
    }
    withAnimation {
      _ = state.pagination.applyPage(ids.map(IdentifiedString.init))
      state.pagination.advance(moreAvailable: moreAvailable)
      sectionStates[section] = state
    }
  }

  private func updateWidgetDataIfNeeded(
    section: DashboardSection,
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
