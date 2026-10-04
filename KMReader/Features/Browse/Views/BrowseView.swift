//
// BrowseView.swift
//
//

import SwiftUI

/// Standalone browse page shell: owns the search field, toolbar, navigation
/// title, search query state, and refresh triggers around `BrowseContentView`.
struct BrowseView: View {
  let authViewModel: AuthViewModel
  let fixedContent: BrowseContentType?
  let metadataFilter: MetadataFilterConfig?
  let focusesSearchOnAppear: Bool
  /// iPhone Library tab root mode: no navigation title, no search field, and
  /// no built-in toolbar library button (LibraryBrowseView adds its own). The
  /// library scope is the global dashboard selection.
  let libraryTab: Bool
  /// Search-tab mode (iPhone): show a search placeholder until a query is
  /// entered instead of browsing all content.
  let searchOnly: Bool

  @Environment(\.browseLibrarySelection) private var librarySelection

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("browseContent") private var browseContent: BrowseContentType = .series
  @AppStorage("seriesBrowseLayout") private var seriesBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("bookBrowseLayout") private var bookBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("collectionBrowseLayout") private var collectionBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("readListBrowseLayout") private var readListBrowseLayout: BrowseLayoutMode = .grid

  @State private var refreshTrigger = UUID()
  @State private var initializedLibraryIdsKey: String?
  @State private var isRefreshDisabled = false
  @State private var searchQuery: String = ""
  @State private var activeSearchText: String = ""
  @State private var showLibraryPicker = false
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  @State private var scopeLibraries: [SidebarLibraryItem] = []
  @FocusState private var isSearchFocused: Bool

  init(
    authViewModel: AuthViewModel,
    fixedContent: BrowseContentType? = nil,
    metadataFilter: MetadataFilterConfig? = nil,
    focusesSearchOnAppear: Bool = false,
    libraryTab: Bool = false,
    searchOnly: Bool = false
  ) {
    self.authViewModel = authViewModel
    self.fixedContent = fixedContent
    self.metadataFilter = metadataFilter
    self.focusesSearchOnAppear = focusesSearchOnAppear
    self.libraryTab = libraryTab
    self.searchOnly = searchOnly
  }

  var title: String {
    if libraryTab {
      return String(localized: "tab.library", defaultValue: "Library")
    } else if searchOnly {
      return String(localized: "tab.search", defaultValue: "Search")
    } else if let library = librarySelection {
      return library.name
    } else if let fixedContent {
      return fixedContent.displayName
    } else {
      return String(localized: "title.browse")
    }
  }

  private var resolvedLibraryIdsKey: String {
    if let library = librarySelection {
      return library.libraryId
    }
    return dashboard.libraryIds.joined(separator: ",")
  }

  var body: some View {
    BrowseContentView(
      fixedContent: fixedContent,
      metadataFilter: metadataFilter,
      searchOnly: searchOnly,
      searchText: activeSearchText,
      showsLibraryHeader: !libraryTab,
      refreshTrigger: refreshTrigger,
      showFilterSheet: $showFilterSheet,
      showSavedFilters: $showSavedFilters
    )
    .platformNavigationTitle(title)
    .searchableIfNeeded(text: $searchQuery, enabled: !libraryTab)
    .browseSearchFocus($isSearchFocused, when: focusesSearchOnAppear)
    .onAppear {
      // iPhone Search tab: entering the tab with an empty query activates the
      // search field directly.
      if searchOnly && searchQuery.isEmpty {
        isSearchFocused = true
      }
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        if librarySelection == nil && !libraryTab {
          #if os(macOS)
            ToolbarItem(placement: .navigation) {
              LibraryScopeToolbarButton(libraries: scopeLibraries, isPresented: $showLibraryPicker)
            }
          #else
            ToolbarItem(placement: .cancellationAction) {
              LibraryScopeToolbarButton(libraries: scopeLibraries, isPresented: $showLibraryPicker)
            }
          #endif
        }
        ToolbarItem(placement: .confirmationAction) {
          BrowseActionsMenu(
            layoutMode: browseLayoutBinding,
            showsPresets: effectiveContent == .series || effectiveContent == .books,
            isFilterEnabled: !searchOnly || !activeSearchText.isEmpty,
            onShowPresets: { showSavedFilters = true },
            onShowFilter: { showFilterSheet = true }
          )
        }
      }
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
      .sheet(isPresented: $showSavedFilters) {
        SavedFiltersView(filterType: effectiveContent == .series ? .series : .books)
      }
      .task(id: current.instanceId) {
        await refreshScopeLibraries()
      }
      .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
        guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
        Task {
          await loadScopeLibraries()
        }
      }
    #endif
    .onSubmit(of: .search) {
      activeSearchText = searchQuery
    }
    .onChange(of: searchQuery) { _, newValue in
      if newValue.isEmpty {
        activeSearchText = ""
      }
    }
    .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
      guard librarySelection == nil else { return }
      // Refresh when server switch completes to avoid race condition
      if oldValue && !newValue {
        refreshBrowse()
      }
    }
    .task(id: resolvedLibraryIdsKey) {
      guard !authViewModel.isSwitching else { return }
      guard initializedLibraryIdsKey != resolvedLibraryIdsKey else { return }
      initializedLibraryIdsKey = resolvedLibraryIdsKey
      refreshBrowse()
    }
  }

  private var effectiveContent: BrowseContentType {
    .effective(fixed: fixedContent, libraryScoped: librarySelection != nil, persisted: browseContent)
  }

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    switch effectiveContent {
    case .series: return $seriesBrowseLayout
    case .books: return $bookBrowseLayout
    case .collections: return $collectionBrowseLayout
    case .readlists: return $readListBrowseLayout
    }
  }

  private func refreshBrowse() {
    refreshTrigger = UUID()
    isRefreshDisabled = true
    Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
      isRefreshDisabled = false
    }
  }

  private func refreshScopeLibraries() async {
    do {
      let loaded = try await LibraryScopeLoader.refresh(instanceId: current.instanceId)
      if scopeLibraries != loaded {
        scopeLibraries = loaded
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadScopeLibraries() async {
    do {
      let loaded = try await LibraryScopeLoader.load(instanceId: current.instanceId)
      if scopeLibraries != loaded {
        scopeLibraries = loaded
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
