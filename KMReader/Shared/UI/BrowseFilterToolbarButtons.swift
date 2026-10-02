//
// BrowseFilterToolbarButtons.swift
//
//

import SwiftUI

/// Trailing filter actions for browse pages (Browse, Offline). iPad merges
/// them into one menu: crowded bars push separate buttons into the system
/// overflow menu, where sheet presentations are dropped and the driving
/// state flag sticks, leaving the button dead until the view is recreated.
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

  private var mergesIntoMenu: Bool {
    #if os(iOS)
      return PlatformHelper.isPad
    #else
      return false
    #endif
  }

  var body: some View {
    if mergesIntoMenu {
      Menu {
        if showsSavedFilters {
          Button {
            deferMenuActionPresentation { onShowSavedFilters() }
          } label: {
            Label(String(localized: "Saved Filters"), systemImage: "bookmark")
          }
        }
        Button {
          deferMenuActionPresentation { onShowFilter() }
        } label: {
          Label(String(localized: "Filter"), systemImage: "line.3.horizontal.decrease")
        }
      } label: {
        Image(systemName: "ellipsis")
      }
    } else {
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
