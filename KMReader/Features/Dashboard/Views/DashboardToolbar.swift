//
// DashboardToolbar.swift
//
//

import SwiftUI

/// The dashboard's toolbar content (iOS/macOS only; tvOS keeps its header in
/// the content area).
struct DashboardToolbar: ToolbarContent {
  let scopeStore: LibraryScopeStore
  @Binding var showLibraryPicker: Bool
  @Binding var scope: LibraryBrowseScope

  var body: some ToolbarContent {
    InlineLargeTitleToolbarItem(title: String(localized: "title.dashboard"))

    LibraryScopeToolbarItem(separatesTrailingMenu: true) {
      DashboardScopeMenu(scopeStore: scopeStore, showLibraryPicker: $showLibraryPicker, scope: $scope)
    }

    #if os(iOS)
      if !PlatformHelper.isPad {
        // iPhone has no Settings tab; keep the entry available in offline mode.
        ToolbarItem(placement: .confirmationAction) {
          NavigationLink(value: NavDestination.settings) {
            Image(systemName: AppIcon.settings)
          }
        }
      }
    #endif
  }
}
