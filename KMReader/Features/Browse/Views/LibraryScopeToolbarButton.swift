//
// LibraryScopeToolbarButton.swift
//
//

import SwiftUI

/// Library scope filter button, icon-only on iOS and macOS. iPhone places it
/// at the trailing toolbar edge, left of the actions menu; iPad and macOS
/// place it at the leading edge (`.cancellationAction` / `.navigation`). The
/// icon is the lines glyph (Apple Books style, near-square so the glass
/// capsule stays round): plain for all libraries, `decrease` for a single
/// library, `checklist` for a multi-library subset (the picker's own
/// multiple-select glyph). The scope name stays available through the
/// accessibility label and hover tooltip. Parents own the library list, the
/// visibility condition, and the LibraryPickerSheet presentation; this view
/// is only the button label.
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

  private var scopeIcon: String {
    let selectedIds = dashboard.libraryIds
    if selectedIds.count == 1, libraries.count > 1 {
      return "line.3.horizontal.decrease"
    }
    if !selectedIds.isEmpty, selectedIds.count < libraries.count {
      return "checklist"
    }
    return "line.3.horizontal"
  }

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: scopeIcon)
        .contentTransition(.symbolEffect(.replace))
    }
    .accessibilityLabel(scopeTitle)
    .help(scopeTitle)
  }
}
