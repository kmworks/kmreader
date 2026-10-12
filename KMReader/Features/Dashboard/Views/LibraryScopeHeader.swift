//
// LibraryScopeHeader.swift
//
//

import SwiftUI

/// Library identity line shown on the Dashboard for the active scope: icon
/// and title matching the scope menu (books.vertical for All/a library, pin
/// for Pinned), then a single truncating facts line — file size first, then
/// series/books counts (admin-only metrics; the line degrades to the bare
/// title without them). The row always renders — the title stays blank until
/// the library list arrives — so the sections below never jump when it appears.
struct LibraryScopeHeader: View {
  let scope: LibraryBrowseScope
  let pinnedIds: [String]
  let libraries: [SidebarLibraryItem]
  let allLibrariesEntry: SidebarLibraryItem?

  @AppStorage("showDashboardSectionGradientBackground")
  private var showGradientBackground: Bool =
    AppConfig.showDashboardSectionGradientBackground

  private var icon: String {
    switch scope {
    case .all, .library:
      return ContentIcon.library
    case .pinned:
      return "pin"
    }
  }

  private var factsText: Text? {
    guard
      let facts = scope.facts(
        pinnedIds: pinnedIds, libraries: libraries, allLibrariesEntry: allLibrariesEntry)
    else { return nil }
    return LibraryMetricsText.sizeAndMetrics(for: facts)
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: icon)
        .font(.body)
        .imageScale(.small)
      // Blank until the library list arrives so the row keeps its height.
      Text(scope.title(pinnedIds: pinnedIds, libraries: libraries) ?? " ")
        .font(.body)
        .lineLimit(1)
      if let factsText {
        factsText
          .font(.footnote)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer()
    }
    .padding(.horizontal)
    .padding(.top, LayoutConfig.dashboardScopeHeaderPadding)
    .padding(
      .bottom,
      showGradientBackground ? LayoutConfig.dashboardScopeHeaderPadding : 0
    )
    #if os(macOS)
      .padding(.leading, 16)
    #endif
  }
}
