//
// DashboardScopeMenu.swift
//
//

import SwiftUI

/// The dashboard toolbar's library scope menu. Reads the scope store itself so
/// the refreshable-carrying `DashboardView` body never observes state its
/// refresh mutates (a carrier re-render cancels the in-flight refresh action).
struct DashboardScopeMenu: View {
  let scopeStore: LibraryScopeStore
  @Binding var showLibraryPicker: Bool
  @Binding var scope: LibraryBrowseScope

  var body: some View {
    LibraryScopeMenu(
      libraries: scopeStore.libraries,
      showLibraryPicker: $showLibraryPicker,
      scope: $scope)
  }
}
