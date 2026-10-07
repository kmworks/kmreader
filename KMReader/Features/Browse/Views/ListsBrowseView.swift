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
  @State private var browseScope: LibraryBrowseScope?
  @State private var showLibraryPicker = false
  @State private var initialLoadDone = false
  @State private var initializedLoadKey: String?
  @State private var collectionsReloadTask: Task<Void, Never>?
  @State private var readListsReloadTask: Task<Void, Never>?
  @State private var smartListsReloadTask: Task<Void, Never>?

  private var effectiveScope: LibraryBrowseScope {
    browseScope ?? .pinned
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

  private var scopeMenuBinding: Binding<LibraryBrowseScope> {
    Binding(get: { effectiveScope }, set: { browseScope = $0 })
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
      #if os(iOS)
        if !PlatformHelper.isPad, #available(iOS 26.0, *) {
          ToolbarItem(placement: .largeTitle) {
            InlineLargeBarTitle(title: String(localized: "tab.lists", defaultValue: "Lists"))
          }
        }
      #endif
      #if os(macOS)
        ToolbarItem(placement: .navigation) {
          LibraryScopeMenu(
            libraries: scopeStore.libraries,
            showLibraryPicker: $showLibraryPicker,
            scope: scopeMenuBinding)
        }
      #endif
      #if os(iOS)
        if PlatformHelper.isPad {
          ToolbarItem(placement: .cancellationAction) {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: scopeMenuBinding)
          }
        } else {
          ToolbarItem(placement: .confirmationAction) {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: scopeMenuBinding)
          }
        }
      #endif
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
    .onChange(of: scopeStore.libraries) { _, libraries in
      // A scoped library that vanished falls back to the aggregate.
      guard !libraries.isEmpty else { return }
      if let scopedId = browseScope?.libraryId,
        !libraries.contains(where: { $0.libraryId == scopedId })
      {
        browseScope = nil
      }
    }
    .onChange(of: dashboard.libraryIds) { _, pinnedIds in
      // The Pinned item only exists while pins do; an emptied pinned set is
      // the full set, which All already represents.
      guard pinnedIds.isEmpty, browseScope == .pinned else { return }
      browseScope = .all
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
