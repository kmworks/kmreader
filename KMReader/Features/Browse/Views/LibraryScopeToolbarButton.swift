//
// LibraryScopeToolbarButton.swift
//
//

import SwiftUI

/// Labeled library scope button for leading toolbar placement (Home, Offline,
/// iPhone Library tab): shows the library icon plus the current dashboard
/// scope (single library name, or the "%lld Libraries" count). iPad keeps the
/// icon only — a wide text button gets pushed into the toolbar's overflow
/// menu when the bar is crowded, and the sidebar already lists the libraries.
/// Parents own the library list, the >1-library visibility condition, and the
/// LibraryPickerSheet presentation; this view is only the button label.
struct LibraryScopeToolbarButton: View {
  let libraries: [SidebarLibraryItem]
  @Binding var isPresented: Bool

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  private var scopeTitle: String {
    let selectedIds = dashboard.libraryIds
    if selectedIds.count == 1,
      let name = libraries.first(where: { $0.libraryId == selectedIds[0] })?.name
    {
      return name
    }
    if libraries.count == 1 {
      return libraries[0].name
    }
    let format = String(
      localized: "offline.coverSync.scope.selected",
      defaultValue: "%lld Libraries"
    )
    return String.localizedStringWithFormat(
      format, selectedIds.isEmpty ? libraries.count : selectedIds.count)
  }

  private var showsScopeTitle: Bool {
    #if os(iOS)
      return !PlatformHelper.isPad
    #else
      return true
    #endif
  }

  var body: some View {
    Button {
      isPresented = true
    } label: {
      // Label gets collapsed to icon-only in the iOS 26 glass toolbar;
      // compose icon + text explicitly.
      HStack(spacing: 4) {
        Image(systemName: ContentIcon.library)
        if showsScopeTitle {
          Text(scopeTitle)
        }
      }
    }
    .accessibilityLabel(scopeTitle)
    .help(scopeTitle)
  }
}
