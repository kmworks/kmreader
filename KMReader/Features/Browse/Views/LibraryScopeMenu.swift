//
// LibraryScopeMenu.swift
//
//

import SwiftUI

/// Library scope dropdown. Switches between All Libraries (pins ignored), the
/// pinned aggregate (offered only while pins exist), and a single library. On
/// the Dashboard it re-filters the sections; on iPad/macOS browse roots the
/// pick writes through to the shell's selection (sidebar/tab highlight
/// follows); elsewhere it re-filters the page in place (a pushed sidebar
/// selection is only the initial scope). The pinned-set editor
/// (`LibraryPickerSheet`) is reached through "Pin Libraries…". Individual
/// library rows carry no icon — the glyphs are reserved for All/Pinned.
struct LibraryScopeMenu: View {
  let libraries: [SidebarLibraryItem]
  @Binding var showLibraryPicker: Bool
  @Binding var scope: LibraryBrowseScope
  /// Toolbars use the icon-only button; the tvOS header shows the scope title.
  var iconOnly: Bool = true

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  private var scopeTitle: String {
    scope.title(pinnedIds: dashboard.libraryIds, libraries: libraries)
      ?? String(localized: "All Libraries")
  }

  private var scopeIcon: String {
    switch scope {
    case .all:
      return "line.3.horizontal"
    case .library:
      return AppIcon.filter
    case .pinned:
      let pinnedIds = dashboard.libraryIds
      if pinnedIds.count == 1, libraries.count > 1 {
        return AppIcon.filter
      }
      if !pinnedIds.isEmpty, pinnedIds.count < libraries.count {
        return "checklist"
      }
      return "line.3.horizontal"
    }
  }

  var body: some View {
    Menu {
      Picker(selection: $scope) {
        Label(String(localized: "All Libraries"), systemImage: ContentIcon.library)
          .tag(LibraryBrowseScope.all)
        if !dashboard.libraryIds.isEmpty {
          Label(
            String(localized: "library.scope.pinned", defaultValue: "Pinned"),
            systemImage: "pin"
          )
          .tag(LibraryBrowseScope.pinned)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()

      Divider()

      Picker(selection: $scope) {
        ForEach(libraries, id: \.libraryId) { library in
          Text(library.name)
            .tag(LibraryBrowseScope.library(library.libraryId))
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()

      Divider()

      Button {
        deferMenuActionPresentation {
          showLibraryPicker = true
        }
      } label: {
        Label(
          String(localized: "library.scope.pin", defaultValue: "Pin Libraries…"),
          systemImage: "checklist"
        )
      }
    } label: {
      if iconOnly {
        Image(systemName: scopeIcon)
          .contentTransition(.symbolEffect(.replace))
      } else {
        Label(scopeTitle, systemImage: scopeIcon)
      }
    }
    .accessibilityLabel(scopeTitle)
    .help(scopeTitle)
  }
}
