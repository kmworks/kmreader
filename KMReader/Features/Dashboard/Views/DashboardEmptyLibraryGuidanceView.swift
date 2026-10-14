//
// DashboardEmptyLibraryGuidanceView.swift
//
//

import SwiftUI

/// The dashboard's empty-library guidance, shown once the library list has
/// loaded empty while online. Reads the scope store itself so the
/// refreshable-carrying `DashboardView` body never observes state its refresh
/// mutates (a carrier re-render cancels the in-flight refresh action).
struct DashboardEmptyLibraryGuidanceView: View {
  let scopeStore: LibraryScopeStore
  let onCreateLibrary: () -> Void

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  var body: some View {
    if scopeStore.hasLoaded && scopeStore.libraries.isEmpty && !isOffline {
      DashboardEmptyLibraryView(isAdmin: current.isAdmin, onCreateLibrary: onCreateLibrary)
    }
  }
}
