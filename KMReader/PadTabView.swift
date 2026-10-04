//
// PadTabView.swift
//
//

import SwiftUI

#if os(iOS)
  @available(iOS 18.0, *)
  struct PadTabView: View {
    /// Library tabs are keyed by library id alone: count updates rebuild the
    /// label without invalidating the selection.
    private enum PadTab: Hashable {
      case home
      case offline
      case server
      case library(String)
      case collections
      case readLists
      case settings
    }

    let context: AppViewContext

    @AppStorage("currentAccount") private var current: Current = .init()

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
          TabSection(String(localized: "Libraries")) {
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
        .environment(\.readerActions, context.readerActions)
        .handleNavigation(context: context)
    }
  }
#endif
