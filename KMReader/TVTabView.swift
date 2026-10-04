//
// TVTabView.swift
//
//

import SwiftUI

#if os(tvOS)
  @available(tvOS 18.0, *)
  struct TVTabView: View {
    let context: AppViewContext
    @State private var selectedTab: TabItem = .home
    @State private var homePath = NavigationPath()

    var body: some View {
      TabView(selection: $selectedTab) {
        Tab(TabItem.home.title, systemImage: TabItem.home.icon, value: TabItem.home) {
          NavigationStack(path: $homePath) {
            rootContent(for: .home)
          }
        }

        Tab(TabItem.offline.title, systemImage: TabItem.offline.icon, value: TabItem.offline) {
          NavigationStack {
            rootContent(for: .offline)
          }
        }

        Tab(TabItem.server.title, systemImage: TabItem.server.icon, value: TabItem.server) {
          NavigationStack {
            rootContent(for: .server)
          }
        }

        Tab(TabItem.settings.title, systemImage: TabItem.settings.icon, value: TabItem.settings) {
          NavigationStack {
            rootContent(for: .settings)
          }
        }

        Tab(TabItem.browse.title, systemImage: TabItem.browse.icon, value: TabItem.browse) {
          NavigationStack {
            rootContent(for: .browse)
          }
        }
      }
      .deepLinkRouting(
        selection: $selectedTab,
        path: $homePath,
        home: .home,
        downloads: .offline,
        search: .browse
      )
    }

    @ViewBuilder
    private func rootContent(for tab: TabItem) -> some View {
      tab.content(context: context)
        .environment(\.readerActions, context.readerActions)
        .handleNavigation(context: context)
    }
  }
#endif
