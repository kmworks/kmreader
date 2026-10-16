//
// DashboardScopeHeaderView.swift
//
//

import SwiftUI

/// The dashboard's library scope header. Reads the scope stores itself so the
/// refreshable-carrying `DashboardView` body never observes state its refresh
/// mutates (a carrier re-render cancels the in-flight refresh action).
struct DashboardScopeHeaderView: View {
  let authViewModel: AuthViewModel
  let scopeStore: LibraryScopeStore
  let dashboardScopeStore: DashboardLibraryScopeStore

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  var body: some View {
    LibraryScopeHeader(
      isConnecting: authViewModel.bootstrapState == .validating,
      scope: dashboardScopeStore.scope,
      pinnedIds: dashboard.libraryIds,
      libraries: scopeStore.libraries,
      allLibrariesEntry: scopeStore.allLibrariesEntry
    )
    .onChange(of: isOffline) { wasOffline, isNowOffline in
      if wasOffline && !isNowOffline {
        Task {
          await scopeStore.refreshMetrics(instanceId: current.instanceId)
        }
      }
    }
  }
}
