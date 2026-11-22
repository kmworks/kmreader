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
    @State private var store = SidebarItemsStore()
    @State private var scopeSelectionStore = LibraryScopeSelectionStore.shared

    @AppStorage("currentAccount") private var current: Current = .init()
    @AppStorage("dashboard") private var dashboard: DashboardConfiguration = .init()
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
        SidebarView(selection: $nav, store: store)
      } detail: {
        PushableNavigationStack(path: $detailPath) {
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
      .onChange(of: dashboard.libraryIds) { _, pinnedIds in
        // The Pinned row only exists while pins do; an emptied pinned set is
        // the full set, which the All row already represents.
        if pinnedIds.isEmpty, nav == .browse(scope: .pinned) {
          nav = .browse(scope: .all)
        }
      }
      .onChange(of: nav) { _, destination in
        guard let scope = destination?.browseScope else { return }
        scopeSelectionStore.scope = scope
      }
      .onChange(of: scopeSelectionStore.scope) { _, _ in
        reconcileBrowseScope()
      }
      .onChange(of: store.libraries) { _, libraries in
        LibraryScopeSelectionStore.shared.librariesDidChange(
          libraries, pinnedIds: dashboard.libraryIds, instanceId: current.instanceId)
        reconcileBrowseScope()
      }
    }

    @ViewBuilder
    private func detailContent(for nav: NavDestination) -> some View {
      nav.content(context: context)
        .environment(\.browseLibrarySelection, librarySelection)
        .environment(\.libraryScopeBinding, nav.libraryScopeBinding(apply: applyScope))
        .environment(\.readerActions, context.readerActions)
        .handleNavigation(context: context)
    }

    /// Applies in-page scope picks to the sidebar selection: choosing a
    /// library selects its sidebar row; choosing All/Pinned selects the
    /// matching aggregate row.
    private func applyScope(_ scope: LibraryBrowseScope) {
      scopeSelectionStore.scope = scope
      reconcileBrowseScope()
      guard let libraryId = scope.libraryId,
        !store.libraries.contains(where: { $0.libraryId == libraryId })
      else { return }
      Task {
        guard await store.load(instanceId: current.instanceId) else { return }
        LibraryScopeSelectionStore.shared.librariesDidChange(
          store.libraries, pinnedIds: dashboard.libraryIds, instanceId: current.instanceId)
        reconcileBrowseScope()
      }
    }

    private func reconcileBrowseScope() {
      guard nav?.browseScope != nil else { return }
      if store.libraries.isEmpty {
        if scopeSelectionStore.scope.libraryId == nil {
          nav = .home
        }
        return
      }
      selectBrowseScope(scopeSelectionStore.scope)
    }

    private func selectBrowseScope(_ scope: LibraryBrowseScope) {
      switch scope {
      case .library(let libraryId):
        guard let item = store.libraries.first(where: { $0.libraryId == libraryId }) else { return }
        nav = .browseLibrary(selection: LibrarySelection(sidebarItem: item))
      case .pinned, .all:
        // The Pinned row is hidden while the pinned set is empty; an emptied
        // pinned set is the full set, which the All row already represents.
        nav = .browse(scope: scope == .pinned && dashboard.libraryIds.isEmpty ? .all : scope)
      }
    }
  }
#endif
