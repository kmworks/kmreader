//
// DashboardSearchResultsView.swift
//
//

import SwiftUI

/// Search results for the Dashboard's `.searchable` overlay: a browse content
/// area driven by the submitted query, with no search field, toolbar, or
/// refresh triggers of its own — the Dashboard underneath owns all chrome and
/// stays mounted, so cancelling a search never reloads sections. Only shown
/// once a query is submitted, so there is no placeholder state.
struct DashboardSearchResultsView: View {
  let searchText: String

  @AppStorage("browseContent") private var browseContent: BrowseContentType = .series
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  @State private var dashboardScopeStore = DashboardLibraryScopeStore.shared
  @State private var refreshTrigger = UUID()
  // The in-content filter bars drive these bindings; without real state the
  // sort/preset chips would be dead buttons here (unlike `BrowseView`, the
  // overlay has no toolbar filter buttons of its own).
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false

  private var effectiveContent: BrowseContentType {
    .effective(fixed: nil, persisted: browseContent)
  }

  var body: some View {
    BrowseContentView(
      searchText: searchText,
      refreshTrigger: refreshTrigger,
      showFilterSheet: $showFilterSheet,
      showSavedFilters: $showSavedFilters,
      libraryIds: dashboardScopeStore.effectiveLibraryIds(pinned: dashboard.libraryIds)
    )
    .background(PlatformHelper.systemBackgroundColor)
    .sheet(isPresented: $showSavedFilters) {
      SavedFiltersView(filterType: effectiveContent == .series ? .series : .books)
    }
  }
}
