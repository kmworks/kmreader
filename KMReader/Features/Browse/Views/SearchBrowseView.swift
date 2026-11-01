//
// SearchBrowseView.swift
//
//

import SwiftUI

/// iPhone Search tab root: search-first browsing. The scope switches in place
/// between All Libraries, the pinned set (default), and a single library.
struct SearchBrowseView: View {
  let authViewModel: AuthViewModel

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("searchBrowseScope") private var scope: LibraryBrowseScope = .pinned

  var body: some View {
    BrowseView(
      authViewModel: authViewModel,
      searchOnly: true,
      libraryIds: scope.resolvedIds(pinned: dashboard.libraryIds),
      libraryTabScope: $scope
    )
  }
}
