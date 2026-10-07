//
// PhoneTabView.swift
//
//

import SwiftUI

#if os(iOS)
  @available(iOS 18.0, *)
  struct PhoneTabView: View {
    let context: AppViewContext
    @State private var readingBarContext = ReadingActionBarContext.shared
    @State private var selectedTab: TabItem = .home
    @State private var homePath = NavigationPath()

    var body: some View {
      rootTabView
        .tabBarMinimizeBehaviorIfAvailable()
        .deepLinkRouting(
          selection: $selectedTab,
          path: $homePath,
          home: .home,
          downloads: .offline,
          search: .browse
        )
    }

    @ViewBuilder
    private var rootTabView: some View {
      if #available(iOS 26.1, *) {
        // Keep the modifier always attached and toggle visibility via
        // isEnabled. Conditionally attaching it would switch ViewBuilder
        // branches, rebuilding the whole tab subtree and resetting detail
        // view state in a refresh loop.
        tabContent
          .tabViewBottomAccessory(isEnabled: readingBarContext.presentation != nil) {
            if let presentation = readingBarContext.presentation {
              SeriesReadingAccessoryView(presentation: presentation) {
                readingBarContext.performAction()
              }
            }
          }
      } else {
        tabContent
      }
    }

    private var tabContent: some View {
      TabView(selection: $selectedTab) {
        Tab(TabItem.home.title, systemImage: TabItem.home.icon, value: TabItem.home) {
          PushableNavigationStack(path: $homePath) {
            rootContent(for: .home)
          }
        }

        Tab(TabItem.library.title, systemImage: TabItem.library.icon, value: TabItem.library) {
          PushableNavigationStack {
            rootContent(for: .library)
          }
        }

        Tab(TabItem.lists.title, systemImage: TabItem.lists.icon, value: TabItem.lists) {
          PushableNavigationStack {
            rootContent(for: .lists)
          }
        }

        Tab(TabItem.offline.title, systemImage: TabItem.offline.icon, value: TabItem.offline) {
          PushableNavigationStack {
            rootContent(for: .offline)
          }
        }

        Tab(
          TabItem.browse.title, systemImage: TabItem.browse.icon, value: TabItem.browse,
          role: .search
        ) {
          PushableNavigationStack {
            rootContent(for: .browse)
          }
        }
      }
    }

    @ViewBuilder
    private func rootContent(for tab: TabItem) -> some View {
      tab.content(context: context)
        .environment(\.readerActions, context.readerActions)
        .handleNavigation(context: context)
    }
  }
#endif
