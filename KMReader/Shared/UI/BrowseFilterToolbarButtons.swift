//
// BrowseFilterToolbarButtons.swift
//
//

import SwiftUI

/// Trailing filter actions for browse pages (Browse, Offline). iPad hides
/// them entirely: the chip row in the page opens the same sheets, and
/// crowded bars push toolbar buttons into the system overflow menu, where
/// sheet presentations are dropped and the driving state flag sticks,
/// leaving the button dead until the view is recreated.
struct BrowseFilterToolbarButtons: View {
  let showsSavedFilters: Bool
  let onShowSavedFilters: () -> Void
  let onShowFilter: () -> Void

  init(
    showsSavedFilters: Bool = true,
    onShowSavedFilters: @escaping () -> Void,
    onShowFilter: @escaping () -> Void
  ) {
    self.showsSavedFilters = showsSavedFilters
    self.onShowSavedFilters = onShowSavedFilters
    self.onShowFilter = onShowFilter
  }

  private var showsToolbarButtons: Bool {
    #if os(iOS)
      return !PlatformHelper.isPad
    #else
      return true
    #endif
  }

  var body: some View {
    if showsToolbarButtons {
      if showsSavedFilters {
        Button(action: onShowSavedFilters) {
          Image(systemName: "bookmark")
        }
        .accessibilityLabel(String(localized: "Saved Filters"))
      }
      Button(action: onShowFilter) {
        Image(systemName: "line.3.horizontal.decrease")
      }
      .accessibilityLabel(String(localized: "Filter"))
    }
  }
}
