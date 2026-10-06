//
// LibraryScopeHeader.swift
//
//

import SwiftUI

/// Library identity line shown on the Dashboard for the active scope: icon
/// and title matching the scope menu (books.vertical for All/a library, pin
/// for Pinned), then a single truncating facts line — file size first, then
/// series/books counts (admin-only metrics; the line degrades to the bare
/// title without them).
struct LibraryScopeHeader: View {
  let scope: LibraryBrowseScope
  let pinnedIds: [String]
  let libraries: [SidebarLibraryItem]
  let allLibrariesEntry: SidebarLibraryItem?

  @AppStorage("showDashboardSectionGradientBackground")
  private var showGradientBackground: Bool =
    AppConfig.showDashboardSectionGradientBackground

  /// Header content for the active scope. Nil when the scoped library is not
  /// in the loaded list.
  private var context: (icon: String, title: String, facts: SidebarLibraryItem?)? {
    guard let title = scope.title(pinnedIds: pinnedIds, libraries: libraries) else { return nil }
    let facts = scope.facts(
      pinnedIds: pinnedIds, libraries: libraries, allLibrariesEntry: allLibrariesEntry)
    switch scope {
    case .all, .library:
      return (ContentIcon.library, title, facts)
    case .pinned:
      return ("pin", title, facts)
    }
  }

  private var factsText: Text? {
    guard let facts = context?.facts else { return nil }
    return LibraryMetricsText.sizeAndMetrics(for: facts)
  }

  var body: some View {
    if let context {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: context.icon)
          .font(.body)
          .imageScale(.small)
        Text(context.title)
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
}
