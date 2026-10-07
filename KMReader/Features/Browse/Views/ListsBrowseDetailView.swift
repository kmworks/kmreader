//
// ListsBrowseDetailView.swift
//
//

import SwiftUI

/// Shell for the Lists page's single-type detail pages (Collections / Read
/// Lists / Smart Lists browse). Split from `BrowseView`: that shell carries
/// the tab-root and search modes plus metadata-filtered series/books pages,
/// while this one only needs the list types' chrome — scope menu (not for
/// smart lists), layout/filter actions, and a plain inline navigation title.
struct ListsBrowseDetailView: View {
  let authViewModel: AuthViewModel
  let fixedContent: ListsBrowseContentType
  let initialScope: LibraryBrowseScope?

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("collectionBrowseLayout") private var collectionBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("readListBrowseLayout") private var readListBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("smartListBrowseLayout") private var smartListBrowseLayout: BrowseLayoutMode = .grid

  @State private var refreshTrigger = UUID()
  @State private var initializedLibraryIdsKey: String?
  @State private var searchQuery: String = ""
  @State private var activeSearchText: String = ""
  @State private var showLibraryPicker = false
  @State private var showFilterSheet = false
  @State private var scopeStore = LibraryScopeStore()
  @State private var browseScope: LibraryBrowseScope?

  init(authViewModel: AuthViewModel, fixedContent: ListsBrowseContentType, initialScope: LibraryBrowseScope? = nil) {
    self.authViewModel = authViewModel
    self.fixedContent = fixedContent
    self.initialScope = initialScope
    _browseScope = State(initialValue: initialScope)
  }

  private var effectiveScope: LibraryBrowseScope {
    browseScope ?? .pinned
  }

  private var menuScopeBinding: Binding<LibraryBrowseScope> {
    Binding(get: { effectiveScope }, set: { browseScope = $0 })
  }

  private var resolvedLibraryIds: [String] {
    effectiveScope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var resolvedLibraryIdsKey: String {
    resolvedLibraryIds.joined(separator: ",")
  }

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    switch fixedContent {
    case .collections: return $collectionBrowseLayout
    case .readlists: return $readListBrowseLayout
    case .smartlists: return $smartListBrowseLayout
    }
  }

  var body: some View {
    BrowseContentView(
      fixedContent: fixedContent.browseContentType,
      searchText: activeSearchText,
      refreshTrigger: refreshTrigger,
      showFilterSheet: $showFilterSheet,
      libraryIds: resolvedLibraryIds,
      scopeLibraries: scopeStore.libraries,
      allLibrariesEntry: scopeStore.allLibrariesEntry
    )
    .inlineNavigationTitle(fixedContent.displayName)
    .searchableIfNeeded(text: $searchQuery, enabled: true)
    #if os(iOS) || os(macOS)
      .toolbar {
        #if os(macOS)
          if fixedContent.supportsLibraryScope {
            ToolbarItem(placement: .navigation) {
              LibraryScopeMenu(
                libraries: scopeStore.libraries,
                showLibraryPicker: $showLibraryPicker,
                scope: menuScopeBinding)
            }
          }
        #endif
        #if os(iOS)
          if PlatformHelper.isPad {
            if fixedContent.supportsLibraryScope {
              ToolbarItem(placement: .cancellationAction) {
                LibraryScopeMenu(
                  libraries: scopeStore.libraries,
                  showLibraryPicker: $showLibraryPicker,
                  scope: menuScopeBinding)
              }
            }
          } else if fixedContent.supportsLibraryScope {
            ToolbarItem(placement: .confirmationAction) {
              LibraryScopeMenu(
                libraries: scopeStore.libraries,
                showLibraryPicker: $showLibraryPicker,
                scope: menuScopeBinding)
            }
            if #available(iOS 26.0, *) {
              ToolbarSpacer(.fixed, placement: .confirmationAction)
            }
          }
        #endif
        ToolbarItem(placement: .confirmationAction) {
          BrowseActionsMenu(
            layoutMode: browseLayoutBinding,
            showsPresets: false,
            isFilterEnabled: fixedContent.supportsLibraryScope,
            onShowPresets: {},
            onShowFilter: { showFilterSheet = true }
          )
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
      activeSearchText = searchQuery
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
      // Refresh when the server switch completes; loading mid-switch races it.
      if oldValue && !newValue {
        refreshTrigger = UUID()
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
}
