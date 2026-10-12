//
// DashboardScopeHeaderView.swift
//
//

import SwiftUI

/// The dashboard's library scope header. Reads the scope stores itself so the
/// refreshable-carrying `DashboardView` body never observes state its refresh
/// mutates (a carrier re-render cancels the in-flight refresh action).
struct DashboardScopeHeaderView: View {
  let scopeStore: LibraryScopeStore
  let dashboardScopeStore: DashboardLibraryScopeStore

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  var body: some View {
    LibraryScopeHeader(
      scope: dashboardScopeStore.scope,
      pinnedIds: dashboard.libraryIds,
      libraries: scopeStore.libraries,
      allLibrariesEntry: scopeStore.allLibrariesEntry)
  }
}
