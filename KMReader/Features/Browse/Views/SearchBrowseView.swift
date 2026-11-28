//
// SearchBrowseView.swift
//
//

import SwiftUI

/// Standalone search page: the iPhone Search tab root (shared root scope) and
/// the pushed deep-link search page on iPad/macOS (page-local scope seeded
/// from the shared root scope). Submits to the all-category search overview;
/// each category strip pushes its own paginated results page.
struct SearchBrowseView: View {
  let authViewModel: AuthViewModel
  let focusesSearchOnAppear: Bool
  /// Tab roots bind the shared root scope; pushed pages keep a local scope.
  private let usesSharedScope: Bool

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var searchViewModel = SearchViewModel()
  @State private var scopeStore = LibraryScopeStore()
  @State private var scopeSelectionStore = LibraryScopeSelectionStore.shared
  @State private var localScope: LibraryBrowseScope
  @State private var searchQuery = ""
  @State private var activeSearchText = ""
  @State private var isSearchPresented = false
  @State private var showLibraryPicker = false
  @FocusState private var isSearchFocused: Bool

  private let title = String(localized: "tab.search", defaultValue: "Search")

  init(
    authViewModel: AuthViewModel,
    focusesSearchOnAppear: Bool = false,
    usesSharedScope: Bool = true,
    initialScope: LibraryBrowseScope? = nil
  ) {
    self.authViewModel = authViewModel
    self.focusesSearchOnAppear = focusesSearchOnAppear
    self.usesSharedScope = usesSharedScope
    _localScope = State(initialValue: initialScope ?? LibraryScopeSelectionStore.shared.scope)
  }

  private var scopeBinding: Binding<LibraryBrowseScope> {
    usesSharedScope ? $scopeSelectionStore.scope : $localScope
  }

  private var effectiveScope: LibraryBrowseScope {
    scopeBinding.wrappedValue
  }

  private var resolvedLibraryIds: [String] {
    effectiveScope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var searchTaskKey: String {
    [
      current.instanceId,
      isOffline ? "offline" : "online",
      resolvedLibraryIds.joined(separator: ","),
      activeSearchText,
    ].joined(separator: "|")
  }

  private var autoFocusesSearchOnAppear: Bool {
    #if os(iOS)
      return !PlatformHelper.isPad
    #else
      return false
    #endif
  }

  /// Only while the iOS 26+ presented search bar hides the toolbar's scope
  /// capsule; dismissing search (or iOS 17's drawer) keeps the toolbar picker
  /// visible, so the placeholder must not render a duplicate.
  private var showsPlaceholderScopeMenu: Bool {
    #if os(iOS)
      if #available(iOS 26.0, *) {
        return !PlatformHelper.isPad && isSearchPresented
      }
      return false
    #else
      return false
    #endif
  }

  var body: some View {
    content
      .inlineLargeBarTitleStyle(enabled: !PlatformHelper.isPad)
      .platformNavigationTitle(title)
      #if os(iOS) || os(macOS)
        .searchableIfNeeded(text: $searchQuery, isPresented: $isSearchPresented, enabled: true)
      #else
        .searchableIfNeeded(text: $searchQuery, enabled: true)
      #endif
      .browseSearchFocus($isSearchFocused, when: focusesSearchOnAppear)
      .onAppear {
        if autoFocusesSearchOnAppear && searchQuery.isEmpty {
          isSearchFocused = true
        }
      }
      #if os(iOS) || os(macOS)
        .toolbar {
          InlineLargeTitleToolbarItem(title: title, enabled: !PlatformHelper.isPad)

          LibraryScopeToolbarItem {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: scopeBinding)
          }
        }
        .sheet(isPresented: $showLibraryPicker) {
          LibraryPickerSheet()
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
      .task(id: searchTaskKey) {
        guard !authViewModel.isSwitching, !activeSearchText.isEmpty else { return }
        guard !searchViewModel.hasLoaded(query: activeSearchText, libraryIds: resolvedLibraryIds)
        else { return }
        await searchViewModel.search(query: activeSearchText, libraryIds: resolvedLibraryIds)
      }
      .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
        guard oldValue && !newValue, !activeSearchText.isEmpty else { return }
        Task {
          await searchViewModel.search(query: activeSearchText, libraryIds: resolvedLibraryIds)
        }
      }
      .onChange(of: scopeStore.libraries) { _, libraries in
        guard !usesSharedScope, let scopedId = localScope.libraryId,
          !libraries.contains(where: { $0.libraryId == scopedId })
        else { return }
        localScope = dashboard.libraryIds.isEmpty ? .all : .pinned
      }
      .onChange(of: dashboard.libraryIds) { _, pinnedIds in
        guard !usesSharedScope, pinnedIds.isEmpty, localScope == .pinned else { return }
        localScope = .all
      }
  }

  @ViewBuilder
  private var content: some View {
    if activeSearchText.isEmpty {
      ScrollView {
        SearchEmptyPlaceholderView(
          libraries: scopeStore.libraries,
          showLibraryPicker: $showLibraryPicker,
          scope: showsPlaceholderScopeMenu ? scopeBinding : nil
        )
      }
    } else {
      SearchResultsContentView(
        query: activeSearchText,
        scope: effectiveScope,
        viewModel: searchViewModel
      )
      .refreshableWithMinimumHold {
        await searchViewModel.search(query: activeSearchText, libraryIds: resolvedLibraryIds)
      }
    }
  }
}
