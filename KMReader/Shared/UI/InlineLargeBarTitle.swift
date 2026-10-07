//
// InlineLargeBarTitle.swift
//
//

import SwiftUI

/// iPhone tab-root title rendered in the navigation bar row (Apple Books
/// style) via `ToolbarItem(placement: .largeTitle)` — the only placement
/// that lands leading on the bar row for every page (`.title` centers on
/// some pages). The system hides and restores it on scroll by itself; the
/// bar and its buttons stay, and the system navigation title stays empty
/// because a collapsed bar title must never appear. iOS 26+ only.
struct InlineLargeBarTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title.bold())
      .fontDesign(.serif)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension View {
  /// The bar presentation that goes with `InlineLargeBarTitle`: inline-large
  /// display mode (required for the `.largeTitle` item to render — and it
  /// must sit under the page's `.inline` pin or the item is dropped), the
  /// bar background and the top scroll-edge blur stay hidden even when
  /// content scrolls under them, so only the floating buttons remain.
  /// No-op before iOS 26 and outside iOS, where the title item is not shown.
  @ViewBuilder
  func inlineLargeBarTitleStyle(enabled: Bool = true) -> some View {
    #if os(iOS)
      if enabled, #available(iOS 26.0, *) {
        self
          .toolbarTitleDisplayMode(.inlineLarge)
          .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
          .scrollEdgeEffectHidden(true, for: .top)
      } else {
        self
      }
    #else
      self
    #endif
  }
}
