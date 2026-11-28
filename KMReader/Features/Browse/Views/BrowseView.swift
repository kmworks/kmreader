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
  /// iPhone Library tab root mode: no search field; the root scope switches
  /// between All Libraries, the pinned set, and a single library in place.
  let libraryTab: Bool
  /// Explicit library scope (empty = all libraries). When nil, the page's
  /// session scope applies.
  let libraryIds: [String]?
  /// iPhone Library tab root scope binding: drives the scope menu and renders
  /// the scope header from it.
  let libraryTabScope: Binding<LibraryBrowseScope>?

  @Environment(\.browseLibrarySelection) private var librarySelection
  @Environment(\.libraryScopeBinding) private var shellScope

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("browseContent") private var browseContent: BrowseContentType = .series
  @AppStorage("seriesBrowseLayout") private var seriesBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("bookBrowseLayout") private var bookBrowseLayout: BrowseLayoutMode = .grid

  @State private var refreshTrigger = UUID()
  @State private var initializedLibraryIdsKey: String?
  @State private var searchQuery: String = ""
  @State private var activeSearchText: String = ""
  @State private var searchViewModel = SearchViewModel()
  @State private var showLibraryPicker = false
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  @State private var scopeStore = LibraryScopeStore()
  /// Page-local session scope for pages the shell does not sync (pushed
  /// pages); a pushed sidebar selection is only its initial value.
  @State private var browseScope: LibraryBrowseScope?
  @FocusState private var isSearchFocused: Bool

  init(
    authViewModel: AuthViewModel,
    fixedContent: BrowseContentType? = nil,
    metadataFilter: MetadataFilterConfig? = nil,
    focusesSearchOnAppear: Bool = false,
    libraryTab: Bool = false,
    libraryIds: [String]? = nil,
    libraryTabScope: Binding<LibraryBrowseScope>? = nil,
    initialScope: LibraryBrowseScope? = nil
  ) {
    self.authViewModel = authViewModel
    self.fixedContent = fixedContent
    self.metadataFilter = metadataFilter
    self.focusesSearchOnAppear = focusesSearchOnAppear
    self.libraryTab = libraryTab
    self.libraryIds = libraryIds
    self.libraryTabScope = libraryTabScope
    _browseScope = State(initialValue: initialScope)
  }

  var title: String {
    if libraryTab {
      return String(localized: "tab.library", defaultValue: "Library")
    } else if librarySelection != nil || shellScope != nil {
      return effectiveScope.title(pinnedIds: dashboard.libraryIds, libraries: scopeStore.libraries)
        ?? librarySelection?.name
        ?? String(localized: "title.browse")
    } else if let fixedContent {
      return fixedContent.displayName
    } else {
      return String(localized: "title.browse")
    }
  }

  /// The page's active scope: the shell-owned scope when the shell syncs one
  /// (iPad/macOS roots), then the page-local session choice, then the pushed
  /// single-library selection as the initial value, then All for an unscoped page.
  private var effectiveScope: LibraryBrowseScope {
    if let shellScope { return shellScope.wrappedValue }
    if let browseScope { return browseScope }
    if let library = librarySelection { return .library(library.libraryId) }
    #if os(tvOS)
      // The tvOS Browse tab is a root without a shell scope binding.
      return LibraryScopeSelectionStore.shared.scope
    #else
      return .all
    #endif
  }

  /// The scope menu's binding: shell scope (writes through to the shell's
  /// selection), else the iPhone tab root scope, else the session scope.
  private var menuScopeBinding: Binding<LibraryBrowseScope> {
    if let shellScope { return shellScope }
    if let libraryTabScope { return libraryTabScope }
    return Binding(get: { effectiveScope }, set: { browseScope = $0 })
  }

  private var resolvedLibraryIds: [String] {
    if let libraryIds {
      return libraryIds
    }
    return effectiveScope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var resolvedLibraryIdsKey: String {
    resolvedLibraryIds.joined(separator: ",")
  }

  /// Aggregate and single-library browse pages (including tvOS Browse) search
  /// across all categories on submit; metadata-filtered and fixed-type pages
  /// keep filtering their own list.
  private var showsSearchOverview: Bool {
    fixedContent == nil && metadataFilter == nil && !libraryTab && !activeSearchText.isEmpty
  }

  private var searchTaskKey: String {
    [
      current.instanceId,
      isOffline ? "offline" : "online",
      resolvedLibraryIdsKey,
      activeSearchText,
    ].joined(separator: "|")
  }

  var body: some View {
    content
      .inlineLargeBarTitleStyle(enabled: libraryTab && !PlatformHelper.isPad)
      .platformNavigationTitle(title)
      .searchableIfNeeded(text: $searchQuery, enabled: !libraryTab)
      .browseSearchFocus($isSearchFocused, when: focusesSearchOnAppear)
      #if os(iOS) || os(macOS)
        .toolbar {
          InlineLargeTitleToolbarItem(title: title, enabled: libraryTab)

          LibraryScopeToolbarItem(
            showsOnPhone: librarySelection == nil,
            separatesTrailingMenu: !showsSearchOverview
          ) {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: menuScopeBinding)
          }

          if !showsSearchOverview {
            ToolbarItem(placement: .confirmationAction) {
              BrowseActionsMenu(
                layoutMode: browseLayoutBinding,
                showsPresets: true,
                isFilterEnabled: true,
                onShowPresets: { showSavedFilters = true },
                onShowFilter: { showFilterSheet = true }
              )
            }
          }
        }
        .sheet(isPresented: $showLibraryPicker) {
          LibraryPickerSheet()
        }
        .sheet(isPresented: $showSavedFilters) {
          SavedFiltersView(filterType: effectiveContent == .series ? .series : .books)
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
      .task(id: searchTaskKey) {
        guard showsSearchOverview, !authViewModel.isSwitching else { return }
        guard !searchViewModel.hasLoaded(query: activeSearchText, libraryIds: resolvedLibraryIds)
        else { return }
        await searchViewModel.search(query: activeSearchText, libraryIds: resolvedLibraryIds)
      }
      .onChange(of: searchQuery) { _, newValue in
        if newValue.isEmpty {
          activeSearchText = ""
        }
      }
      .onChange(of: librarySelection) { _, _ in
        // A reused page (macOS split detail) must not keep the previous
        // library's scope.
        browseScope = nil
      }
      .onChange(of: scopeStore.libraries) { _, libraries in
        // A page-local scoped library that vanished falls back to the aggregate.
        if let scopedId = browseScope?.libraryId,
          !libraries.contains(where: { $0.libraryId == scopedId })
        {
          browseScope = dashboard.libraryIds.isEmpty ? .all : .pinned
        }
      }
      .onChange(of: dashboard.libraryIds) { _, pinnedIds in
        // The Pinned item only exists while pins do; an emptied pinned set is
        // the full set, which All already represents.
        guard pinnedIds.isEmpty else { return }
        if browseScope == .pinned {
          browseScope = .all
        }
      }
      .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
        guard librarySelection == nil else { return }
        // Refresh when server switch completes to avoid race condition
        if oldValue && !newValue {
          refreshBrowse()
          if showsSearchOverview {
            Task {
              await searchViewModel.search(query: activeSearchText, libraryIds: resolvedLibraryIds)
            }
          }
        }
      }
      .task(id: resolvedLibraryIdsKey) {
        guard !authViewModel.isSwitching else { return }
        guard initializedLibraryIdsKey != resolvedLibraryIdsKey else { return }
        initializedLibraryIdsKey = resolvedLibraryIdsKey
        refreshBrowse()
      }
  }

  @ViewBuilder
  private var content: some View {
    if showsSearchOverview {
      SearchResultsContentView(
        query: activeSearchText,
        scope: effectiveScope,
        viewModel: searchViewModel
      )
      .refreshableWithMinimumHold {
        await searchViewModel.search(query: activeSearchText, libraryIds: resolvedLibraryIds)
      }
    } else {
      BrowseContentView(
        fixedContent: fixedContent,
        metadataFilter: metadataFilter,
        searchText: activeSearchText,
        refreshTrigger: refreshTrigger,
        showFilterSheet: $showFilterSheet,
        showSavedFilters: $showSavedFilters,
        libraryIds: resolvedLibraryIds,
        libraryScope: libraryTab ? libraryTabScope?.wrappedValue : effectiveScope,
        scopeLibraries: scopeStore.libraries,
        allLibrariesEntry: scopeStore.allLibrariesEntry
      )
    }
  }

  private var effectiveContent: BrowseContentType {
    .effective(fixed: fixedContent, persisted: browseContent)
  }

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    switch effectiveContent {
    case .series: return $seriesBrowseLayout
    case .books: return $bookBrowseLayout
    // effectiveContent is series/books here: fixedContent is only ever
    // series/books on this page since the list types split out.
    default: return $seriesBrowseLayout
    }
  }

  private func refreshBrowse() {
    refreshTrigger = UUID()
  }
}
