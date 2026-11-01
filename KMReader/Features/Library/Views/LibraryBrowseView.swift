//
// LibraryBrowseView.swift
//
//

import SwiftUI

/// iPhone Library tab root: content-first browsing (Apple Books style). The
/// root scope switches in place between All Libraries, the pinned set
/// (default), and a single library. Library management stays in Settings.
struct LibraryBrowseView: View {
  let authViewModel: AuthViewModel

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("libraryBrowseScope") private var scope: LibraryBrowseScope = .pinned

  var body: some View {
    BrowseView(
      authViewModel: authViewModel,
      libraryTab: true,
      libraryIds: scope.resolvedIds(pinned: dashboard.libraryIds),
      libraryTabScope: $scope
    )
  }
}
