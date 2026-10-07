//
// OldTabView.swift
//
//

import SwiftUI

struct OldTabView: View {
  let context: AppViewContext
  @State private var selectedTab: TabItem = .home
  @State private var homePath = NavigationPath()

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack(path: $homePath) {
        rootContent(for: .home)
      }
      .tabItem { TabItem.home.label }
      .tag(TabItem.home)

      #if os(iOS)
        NavigationStack {
          rootContent(for: .library)
        }
        .tabItem { TabItem.library.label }
        .tag(TabItem.library)

        NavigationStack {
          rootContent(for: .lists)
        }
        .tabItem { TabItem.lists.label }
        .tag(TabItem.lists)
      #endif

      NavigationStack {
        rootContent(for: .offline)
      }
      .tabItem { TabItem.offline.label }
      .tag(TabItem.offline)

      #if os(tvOS)
        NavigationStack {
          rootContent(for: .server)
        }
        .tabItem { TabItem.server.label }
        .tag(TabItem.server)

        NavigationStack {
          rootContent(for: .settings)
        }
        .tabItem { TabItem.settings.label }
        .tag(TabItem.settings)
      #endif

      NavigationStack {
        rootContent(for: .browse)
      }
      .tabItem { TabItem.browse.label }
      .tag(TabItem.browse)
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
