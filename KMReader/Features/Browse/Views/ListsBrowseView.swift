//
// ListsBrowseView.swift
//
//

import SwiftUI

/// Lists page: Collections, Read Lists, and Smart Lists as horizontal strips,
/// pinned items first, fed by the same view models as the full single-type
/// pages the section headers link to. The library scope filters the
/// collections/read lists strips; smart lists have no library filter, and
/// their strip hides on Komga servers (no smart-list API) and offline.
///
/// The view models live here, but the strip content that reads them is
/// `ListsBrowseContentView`: an active refresh action is cancelled as soon
/// as the view carrying `.refreshable` re-renders, so this body's only job is
/// chrome (toolbar/sheets) plus the awaited `reloadAll()`.
struct ListsBrowseView: View {
  let authViewModel: AuthViewModel

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = .init()

  @State private var collectionsViewModel = CollectionsViewModel(pageSize: 20)
  @State private var readListsViewModel = ReadListsViewModel(pageSize: 20)
  @State private var smartListsViewModel = SmartListsViewModel()
  @State private var scopeStore = LibraryScopeStore()
  @State private var scopeSelectionStore = LibraryScopeSelectionStore.shared
  @State private var showLibraryPicker = false
  @State private var initialLoadDone = false
  @State private var initializedLoadKey: String?
  @State private var collectionsReloadTask: Task<Void, Never>?
  @State private var readListsReloadTask: Task<Void, Never>?
  @State private var smartListsReloadTask: Task<Void, Never>?

  private var effectiveScope: LibraryBrowseScope {
    scopeSelectionStore.scope
  }

  private var resolvedLibraryIds: [String] {
    effectiveScope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var loadKey: String {
    "\(current.instanceId)|\(resolvedLibraryIdsKey)"
  }

  private var resolvedLibraryIdsKey: String {
    resolvedLibraryIds.joined(separator: ",")
  }

  var body: some View {
    ListsBrowseContentView(
      collectionsViewModel: collectionsViewModel,
      readListsViewModel: readListsViewModel,
      smartListsViewModel: smartListsViewModel,
      initialLoadDone: initialLoadDone,
      effectiveScope: effectiveScope
    )
    .inlineLargeBarTitleStyle(enabled: !PlatformHelper.isPad)
    .platformNavigationTitle(String(localized: "tab.lists", defaultValue: "Lists"))
    .refreshableWithMinimumHold {
      await reloadAll()
    }
    .toolbar {
      InlineLargeTitleToolbarItem(title: String(localized: "tab.lists", defaultValue: "Lists"))

      LibraryScopeToolbarItem {
        LibraryScopeMenu(
          libraries: scopeStore.libraries,
          showLibraryPicker: $showLibraryPicker,
          scope: $scopeSelectionStore.scope)
      }
    }
    .sheet(isPresented: $showLibraryPicker) {
      LibraryPickerSheet()
    }
    .task(id: loadKey) {
      // Returning from a pushed child re-fires this task; skip re-fires for
      // the same key so the strips don't re-sync or reset pagination.
      guard !authViewModel.isSwitching, initializedLoadKey != loadKey else { return }
      initializedLoadKey = loadKey
      await reloadAll()
      initialLoadDone = true
    }
    .task(id: current.instanceId) {
      await scopeStore.refresh(instanceId: current.instanceId)
    }
    .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
      guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
      Task {
        await scopeStore.load(instanceId: current.instanceId)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .collectionProjectionDidChange)) { _ in
      // Projection posts arrive per id; coalesce a burst into one reload.
      collectionsReloadTask?.cancel()
      collectionsReloadTask = Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        await collectionsViewModel.loadCollections(
          libraryIds: resolvedLibraryIds, refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .readListProjectionDidChange)) { _ in
      readListsReloadTask?.cancel()
      readListsReloadTask = Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        await readListsViewModel.loadReadLists(
          libraryIds: resolvedLibraryIds, refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListsDidChange)) { _ in
      smartListsReloadTask?.cancel()
      smartListsReloadTask = Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        await smartListsViewModel.loadSmartLists(refresh: true)
      }
    }
    .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
      // Refresh when the server switch completes; loading mid-switch races it.
      if oldValue && !newValue {
        Task {
          initializedLoadKey = loadKey
          await reloadAll()
          initialLoadDone = true
        }
      }
    }
  }

  private func reloadAll() async {
    async let loadCollections: Void = collectionsViewModel.loadCollections(
      libraryIds: resolvedLibraryIds, refresh: true)
    async let loadReadLists: Void = readListsViewModel.loadReadLists(
      libraryIds: resolvedLibraryIds, refresh: true)
    async let loadSmartLists: Void = smartListsViewModel.loadSmartLists(refresh: true)
    _ = await (loadCollections, loadReadLists, loadSmartLists)
  }
}
