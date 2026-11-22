//
// SearchBrowseView.swift
//
//

import SwiftUI

/// iPhone Search tab root: search-first browsing. The scope switches in place
/// between All Libraries, the pinned set (the default when pins exist), and a single library.
struct SearchBrowseView: View {
  let authViewModel: AuthViewModel

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @State private var scopeSelectionStore = LibraryScopeSelectionStore.shared

  var body: some View {
    BrowseView(
      authViewModel: authViewModel,
      searchOnly: true,
      libraryIds: scopeSelectionStore.scope.resolvedIds(pinned: dashboard.libraryIds),
      libraryTabScope: $scopeSelectionStore.scope
    )
  }
}
