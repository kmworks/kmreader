//
// LibraryScopeToolbarItem.swift
//
//

import SwiftUI

/// Wraps content (usually a `LibraryScopeMenu`) as the page's scope toolbar
/// item with the platform's placement: macOS and iPad lead (`.navigation` /
/// `.cancellationAction`), iPhone trails (`.confirmationAction`).
struct LibraryScopeToolbarItem<Content: View>: ToolbarContent {
  /// Master visibility gate (Offline hides the menu on pushed single-library
  /// pages on every platform).
  let isVisible: Bool
  /// Extra iPhone-only gate: pushed single-library browse pages hide the menu
  /// on iPhone only; iPad and macOS keep it.
  let showsOnPhone: Bool
  /// iPhone only: adds the fixed spacer separating the scope capsule from the
  /// trailing item.
  let separatesTrailingMenu: Bool
  @ViewBuilder let content: () -> Content

  init(
    isVisible: Bool = true,
    showsOnPhone: Bool = true,
    separatesTrailingMenu: Bool = false,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.isVisible = isVisible
    self.showsOnPhone = showsOnPhone
    self.separatesTrailingMenu = separatesTrailingMenu
    self.content = content
  }

  var body: some ToolbarContent {
    #if os(macOS)
      if isVisible {
        ToolbarItem(placement: .navigation) { content() }
      }
    #elseif os(iOS)
      if isVisible && (PlatformHelper.isPad || showsOnPhone) {
        ToolbarItem(placement: PlatformHelper.isPad ? .cancellationAction : .confirmationAction) {
          content()
        }
        if separatesTrailingMenu && !PlatformHelper.isPad, #available(iOS 26.0, *) {
          ToolbarSpacer(.fixed, placement: .confirmationAction)
        }
      }
    #endif
  }
}
