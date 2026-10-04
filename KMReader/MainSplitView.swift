//
// MainSplitView.swift
//
//

import SwiftUI

#if os(iOS) || os(macOS)
  struct MainSplitView: View {
    let context: AppViewContext
    @State private var nav: NavDestination? = .home
    @State private var detailPath = NavigationPath()
    #if os(macOS)
      @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #else
      @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    #endif

    var librarySelection: LibrarySelection? {
      guard let nav else { return nil }
      switch nav {
      case .browseLibrary(let library):
        return library
      default:
        return nil
      }
    }

    var body: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarView(selection: $nav)
      } detail: {
        NavigationStack(path: $detailPath) {
          if let nav {
            // Recreate the detail root per selection: same-type swaps
            // (collection A → B) otherwise keep the previous view's state,
            // leaving stale content behind.
            detailContent(for: nav)
              .id(nav)
          } else {
            ContentUnavailableView {
              Label(String(localized: "Select a Category"), systemImage: "sidebar.left")
            } description: {
              Text(String(localized: "Pick something from the sidebar to get started."))
            }
          }
        }
      }
      .deepLinkRouting(
        selection: $nav,
        path: $detailPath,
        home: .home,
        downloads: .offline,
        search: .browseSearch
      )
    }

    @ViewBuilder
    private func detailContent(for nav: NavDestination) -> some View {
      nav.content(context: context)
        .environment(\.browseLibrarySelection, librarySelection)
        .environment(\.readerActions, context.readerActions)
        .handleNavigation(context: context)
    }
  }
#endif
