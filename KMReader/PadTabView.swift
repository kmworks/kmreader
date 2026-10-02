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

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("currentAccount") private var current: Current = .init()

    @State private var deepLinkRouter = DeepLinkRouter.shared
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
        Tab(TabItem.server.title, systemImage: TabItem.server.icon, value: PadTab.server) {
          NavigationStack {
            rootContent(for: .server)
          }
        }

        // Sections always render after every plain tab in the sidebar,
        // regardless of declaration order.
        if !store.libraries.isEmpty {
          TabSection(String(localized: "Libraries")) {
            ForEach(store.libraries) { library in
              Tab(
                library.name, systemImage: ContentIcon.library,
                value: PadTab.library(library.libraryId)
              ) {
                NavigationStack {
                  rootContent(for: .browseLibrary(selection: LibrarySelection(sidebarItem: library)))
                }
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

        Tab(TabItem.settings.title, systemImage: TabItem.settings.icon, value: PadTab.settings) {
          NavigationStack {
            rootContent(for: .settings)
          }
        }
      }
      .tabViewStyle(.sidebarAdaptable)
      // The sidebar paints the selection pill and unselected row icons with
      // the tint. The near-white dark-mode accent makes the pill unreadable
      // (white-on-white), so dark mode uses a neutral gray light enough for
      // row icons to stay visible. Tab contents re-tint to the accent below.
      .tint(colorScheme == .dark ? Color(uiColor: .systemGray) : Color.accentColor)
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
      .onAppear {
        if let link = deepLinkRouter.pendingDeepLink {
          handleDeepLink(link)
        }
      }
      .onChange(of: deepLinkRouter.pendingDeepLink) { _, link in
        guard let link else { return }
        handleDeepLink(link)
      }
    }

    @ViewBuilder
    private func rootContent(for destination: NavDestination) -> some View {
      destination.content(context: context)
        .environment(\.browseLibrarySelection, destination.librarySelection)
        .environment(\.readerActions, context.readerActions)
        .tint(Color.accentColor)
        .handleNavigation(context: context)
    }

    private func handleDeepLink(_ link: DeepLink) {
      deepLinkRouter.pendingDeepLink = nil
      switch link {
      case .book(let bookId):
        selection = .home
        homePath = NavigationPath()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          homePath.append(NavDestination.bookDetail(bookId: bookId))
        }
      case .series(let seriesId):
        selection = .home
        homePath = NavigationPath()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          homePath.append(NavDestination.seriesDetail(seriesId: seriesId))
        }
      case .search:
        selection = .home
        homePath = NavigationPath()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          homePath.append(NavDestination.browseSearch)
        }
      case .downloads:
        selection = .offline
      }
    }
  }
#endif
