//
// SearchEmptyPlaceholderView.swift
//
//

import SwiftUI

/// Pre-query search prompt. The iPhone Search tab embeds its scope menu here
/// because the auto-focused search field hides the toolbar's scope picker.
struct SearchEmptyPlaceholderView: View {
  let libraries: [SidebarLibraryItem]
  let showLibraryPicker: Binding<Bool>
  let scope: Binding<LibraryBrowseScope>?

  init(
    libraries: [SidebarLibraryItem] = [],
    showLibraryPicker: Binding<Bool> = .constant(false),
    scope: Binding<LibraryBrowseScope>? = nil
  ) {
    self.libraries = libraries
    self.showLibraryPicker = showLibraryPicker
    self.scope = scope
  }

  var body: some View {
    ContentUnavailableView {
      Label(String(localized: "tab.search", defaultValue: "Search"), systemImage: AppIcon.search)
    } description: {
      Text(
        String(
          localized: "search.empty.hint",
          defaultValue: "Search series, books, collections, and read lists."))
    } actions: {
      if let scope {
        LibraryScopeMenu(
          libraries: libraries,
          showLibraryPicker: showLibraryPicker,
          scope: scope,
          iconOnly: false
        )
        .adaptiveButtonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }
}
