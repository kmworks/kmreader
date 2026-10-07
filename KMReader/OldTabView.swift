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
      PushableNavigationStack(path: $homePath) {
        rootContent(for: .home)
      }
      .tabItem { TabItem.home.label }
      .tag(TabItem.home)

      #if os(iOS)
        PushableNavigationStack {
          rootContent(for: .library)
        }
        .tabItem { TabItem.library.label }
        .tag(TabItem.library)

        PushableNavigationStack {
          rootContent(for: .lists)
        }
        .tabItem { TabItem.lists.label }
        .tag(TabItem.lists)
      #endif

      PushableNavigationStack {
        rootContent(for: .offline)
      }
      .tabItem { TabItem.offline.label }
      .tag(TabItem.offline)

      #if os(tvOS)
        PushableNavigationStack {
          rootContent(for: .lists)
        }
        .tabItem { TabItem.lists.label }
        .tag(TabItem.lists)

        PushableNavigationStack {
          rootContent(for: .server)
        }
        .tabItem { TabItem.server.label }
        .tag(TabItem.server)

        PushableNavigationStack {
          rootContent(for: .settings)
        }
        .tabItem { TabItem.settings.label }
        .tag(TabItem.settings)
      #endif

      PushableNavigationStack {
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
