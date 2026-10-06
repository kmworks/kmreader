//
// PadTabView.swift
//
//

import SwiftUI

#if os(iOS)
  @available(iOS 18.0, *)
  struct PadTabView: View {
    /// Library tabs are keyed by library id alone: count updates rebuild the
    /// label without invalidating the selection. Aggregate tabs carry their
    /// scope (only `.all`/`.pinned` occur).
    private enum PadTab: Hashable {
      case home
      case offline
      case server
      case libraries(LibraryBrowseScope)
      case library(String)
      case collections
      case readLists
      case settings
    }

    let context: AppViewContext

    @AppStorage("currentAccount") private var current: Current = .init()
    @AppStorage("dashboard") private var dashboard: DashboardConfiguration = .init()

    @State private var store = SidebarItemsStore()
    @State private var selection: PadTab = .home
    @State private var homePath = NavigationPath()

    var body: some View {
      TabView(selection: $selection) {
        Tab(TabItem.home.title, systemImage: TabItem.home.icon, value: PadTab.home) {
          NavigationStack(path: $homePath) {
            rootContent(for: .home)
          }
        }
        Tab(TabItem.offline.title, systemImage: TabItem.offline.icon, value: PadTab.offline) {
          NavigationStack {
            rootContent(for: .offline)
          }
        }

        // Sections always render after every plain tab in the sidebar,
        // regardless of declaration order.
        if !store.libraries.isEmpty {
          // The aggregate tabs lead the Libraries section itself: splitting
          // them into their own section makes the tab bar's Libraries item
          // land on the first library instead of All Libraries.
          TabSection(String(localized: "Libraries")) {
            Tab(value: PadTab.libraries(.all)) {
              NavigationStack {
                rootContent(for: .browse(scope: .all))
              }
            } label: {
              Text(String(localized: "All Libraries"))
            }
            if !dashboard.libraryIds.isEmpty {
              Tab(value: PadTab.libraries(.pinned)) {
                NavigationStack {
                  rootContent(for: .browse(scope: .pinned))
                }
              } label: {
                Text(String(localized: "library.scope.pinned", defaultValue: "Pinned"))
              }
            }
            ForEach(store.libraries) { library in
              Tab(value: PadTab.library(library.libraryId)) {
                NavigationStack {
                  rootContent(for: .browseLibrary(selection: LibrarySelection(sidebarItem: library)))
                }
              } label: {
                Text(library.name)
              }
            }
          }
        }

        Tab(
          String(localized: "tab.collections"), systemImage: ContentIcon.collection,
          value: PadTab.collections
        ) {
          NavigationStack {
            rootContent(for: .browseCollections)
          }
        }
        Tab(
          String(localized: "tab.readLists"), systemImage: ContentIcon.readList,
          value: PadTab.readLists
        ) {
          NavigationStack {
            rootContent(for: .browseReadLists)
          }
        }

        Tab(TabItem.server.title, systemImage: TabItem.server.icon, value: PadTab.server) {
          NavigationStack {
            rootContent(for: .server)
          }
        }

        Tab(TabItem.settings.title, systemImage: TabItem.settings.icon, value: PadTab.settings) {
          NavigationStack {
            rootContent(for: .settings)
          }
        }
      }
      .tabViewStyle(.sidebarAdaptable)
      .tabBarMinimizeBehaviorIfAvailable()
      .task(id: current.instanceId) {
        await store.load(instanceId: current.instanceId)
      }
      .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) {
        notification in
        guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
        Task {
          await store.load(instanceId: current.instanceId)
        }
      }
      .onChange(of: store.libraries) { _, libraries in
        guard case .library(let libraryId) = selection else { return }
        if !libraries.contains(where: { $0.libraryId == libraryId }) {
          selection = .home
        }
      }
      .onChange(of: dashboard.libraryIds) { _, pinnedIds in
        // The Pinned tab only exists while pins do; an emptied pinned set is
        // the full set, which the All tab already represents.
        if pinnedIds.isEmpty, selection == .libraries(.pinned) {
          selection = .libraries(.all)
        }
      }
      .deepLinkRouting(
        selection: $selection,
        path: $homePath,
        home: .home,
        downloads: .offline,
        searchDestination: .browseSearch
      )
    }

    @ViewBuilder
    private func rootContent(for destination: NavDestination) -> some View {
      destination.content(context: context)
        .environment(\.browseLibrarySelection, destination.librarySelection)
        .environment(\.libraryScopeBinding, scopeBinding(for: destination))
        .environment(\.readerActions, context.readerActions)
        .handleNavigation(context: context)
    }

    /// Scope binding that keeps the tab selection in sync with in-page picks:
    /// choosing a library switches to its tab; choosing All/Pinned switches to
    /// the matching aggregate tab.
    private func scopeBinding(for destination: NavDestination) -> Binding<LibraryBrowseScope>? {
      switch destination {
      case .browse(let scope):
        return Binding(
          get: { scope },
          set: { applyScope($0) })
      case .browseLibrary(let librarySelection):
        return Binding(
          get: { .library(librarySelection.libraryId) },
          set: { applyScope($0) })
      default:
        return nil
      }
    }

    private func applyScope(_ scope: LibraryBrowseScope) {
      switch scope {
      case .library(let libraryId):
        selection = .library(libraryId)
      case .pinned, .all:
        // The Pinned tab is hidden while the pinned set is empty; an emptied
        // pinned set is the full set, which the All tab already represents.
        selection = .libraries(scope == .pinned && dashboard.libraryIds.isEmpty ? .all : scope)
      }
    }
  }
#endif
