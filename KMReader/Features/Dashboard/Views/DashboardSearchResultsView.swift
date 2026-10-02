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

  @State private var refreshTrigger = UUID()

  var body: some View {
    BrowseContentView(
      searchText: searchText,
      refreshTrigger: refreshTrigger
    )
    .background(PlatformHelper.systemBackgroundColor)
  }
}
