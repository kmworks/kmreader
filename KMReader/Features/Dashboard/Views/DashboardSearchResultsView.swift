//
// DashboardSearchResultsView.swift
//
//

import SwiftUI

/// All-category search results for the Dashboard's `.searchable` overlay on
/// iPad/macOS. The Dashboard stays mounted underneath so cancelling a search
/// never reloads sections; tapping a category strip pushes its full results
/// page onto the enclosing stack, and popping back keeps this overlay intact.
struct DashboardSearchResultsView: View {
  let authViewModel: AuthViewModel
  let searchText: String

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var scopeSelectionStore = LibraryScopeSelectionStore.shared
  @State private var viewModel = SearchViewModel()

  private var libraryIds: [String] {
    scopeSelectionStore.effectiveLibraryIds(pinned: dashboard.libraryIds)
  }

  private var searchTaskKey: String {
    [
      current.instanceId,
      isOffline ? "offline" : "online",
      libraryIds.joined(separator: ","),
      searchText,
    ].joined(separator: "|")
  }

  var body: some View {
    SearchResultsContentView(
      query: searchText,
      scope: scopeSelectionStore.scope,
      viewModel: viewModel
    )
    .background(PlatformHelper.systemBackgroundColor)
    .refreshableWithMinimumHold {
      await viewModel.search(query: searchText, libraryIds: libraryIds)
    }
    .task(id: searchTaskKey) {
      guard !authViewModel.isSwitching else { return }
      guard !viewModel.hasLoaded(query: searchText, libraryIds: libraryIds) else { return }
      await viewModel.search(query: searchText, libraryIds: libraryIds)
    }
    .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
      guard oldValue && !newValue else { return }
      Task {
        await viewModel.search(query: searchText, libraryIds: libraryIds)
      }
    }
  }
}
