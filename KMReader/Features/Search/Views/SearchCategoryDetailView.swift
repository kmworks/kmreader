//
// SearchCategoryDetailView.swift
//
//

import SwiftUI

/// Paginated search results for a single category (Series / Books /
/// Collections / Read Lists), pushed from the all-category search overview.
/// Carries the query and scope it was opened with; editing the search field
/// re-queries this category in place, and scope changes stay page-local.
struct SearchCategoryDetailView: View {
  let authViewModel: AuthViewModel
  let category: BrowseContentType

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("seriesBrowseLayout") private var seriesBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("bookBrowseLayout") private var bookBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("collectionBrowseLayout") private var collectionBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("readListBrowseLayout") private var readListBrowseLayout: BrowseLayoutMode = .grid

  @State private var refreshTrigger = UUID()
  @State private var initializedLibraryIdsKey: String?
  @State private var searchQuery: String
  @State private var activeSearchText: String
  @State private var showLibraryPicker = false
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  @State private var scopeStore = LibraryScopeStore()
  @State private var browseScope: LibraryBrowseScope

  init(
    authViewModel: AuthViewModel,
    category: BrowseContentType,
    query: String,
    scope: LibraryBrowseScope
  ) {
    self.authViewModel = authViewModel
    self.category = category
    _searchQuery = State(initialValue: query)
    _activeSearchText = State(initialValue: query)
    _browseScope = State(initialValue: scope)
  }

  private var supportsPresets: Bool {
    category == .series || category == .books
  }

  private var resolvedLibraryIds: [String] {
    browseScope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var resolvedLibraryIdsKey: String {
    resolvedLibraryIds.joined(separator: ",")
  }

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    switch category {
    case .books: return $bookBrowseLayout
    case .collections: return $collectionBrowseLayout
    case .readlists: return $readListBrowseLayout
    case .series, .smartlists: return $seriesBrowseLayout
    }
  }

  var body: some View {
    Group {
      if activeSearchText.isEmpty {
        ScrollView {
          SearchEmptyPlaceholderView()
        }
      } else {
        BrowseContentView(
          fixedContent: category,
          searchText: activeSearchText,
          refreshTrigger: refreshTrigger,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: $showSavedFilters,
          libraryIds: resolvedLibraryIds,
          scopeLibraries: scopeStore.libraries,
          allLibrariesEntry: scopeStore.allLibrariesEntry
        )
      }
    }
    .inlineNavigationTitle(category.displayName)
    .searchableIfNeeded(text: $searchQuery, enabled: true)
    #if os(iOS) || os(macOS)
      .toolbar {
        LibraryScopeToolbarItem(separatesTrailingMenu: true) {
          LibraryScopeMenu(
            libraries: scopeStore.libraries,
            showLibraryPicker: $showLibraryPicker,
            scope: $browseScope)
        }

        ToolbarItem(placement: .confirmationAction) {
          BrowseActionsMenu(
            layoutMode: browseLayoutBinding,
            showsPresets: supportsPresets,
            isFilterEnabled: !activeSearchText.isEmpty,
            onShowPresets: { showSavedFilters = true },
            onShowFilter: { showFilterSheet = true }
          )
        }
      }
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
      .sheet(isPresented: $showSavedFilters) {
        SavedFiltersView(filterType: category == .books ? .books : .series)
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
    #endif
    .onSubmit(of: .search) {
      activeSearchText = SearchViewModel.normalizedQuery(searchQuery)
    }
    .onChange(of: searchQuery) { _, newValue in
      if newValue.isEmpty {
        activeSearchText = ""
      }
    }
    .task(id: resolvedLibraryIdsKey) {
      guard !authViewModel.isSwitching else { return }
      guard initializedLibraryIdsKey != resolvedLibraryIdsKey else { return }
      initializedLibraryIdsKey = resolvedLibraryIdsKey
      refreshTrigger = UUID()
    }
    .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
      if oldValue && !newValue {
        refreshTrigger = UUID()
      }
    }
    .onChange(of: scopeStore.libraries) { _, libraries in
      if let scopedId = browseScope.libraryId,
        !libraries.contains(where: { $0.libraryId == scopedId })
      {
        browseScope = dashboard.libraryIds.isEmpty ? .all : .pinned
      }
    }
    .onChange(of: dashboard.libraryIds) { _, pinnedIds in
      guard pinnedIds.isEmpty, browseScope == .pinned else { return }
      browseScope = .all
    }
  }
}
