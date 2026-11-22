//
// LibraryBrowseView.swift
//
//

import SwiftUI

/// iPhone Library tab root: content-first browsing (Apple Books style). The
/// root scope switches in place between All Libraries, the pinned set
/// (the default when pins exist), and a single library. Library management stays in Settings.
struct LibraryBrowseView: View {
  let authViewModel: AuthViewModel

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @State private var scopeSelectionStore = LibraryScopeSelectionStore.shared

  var body: some View {
    BrowseView(
      authViewModel: authViewModel,
      libraryTab: true,
      libraryIds: scopeSelectionStore.scope.resolvedIds(pinned: dashboard.libraryIds),
      libraryTabScope: $scopeSelectionStore.scope
    )
  }
}
