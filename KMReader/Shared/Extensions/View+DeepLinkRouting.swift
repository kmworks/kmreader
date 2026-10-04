//
// View+DeepLinkRouting.swift
//
//

import SwiftUI

private struct DeepLinkRoutingModifier<Selection: Equatable>: ViewModifier {
  @State private var router = DeepLinkRouter.shared

  @Binding var selection: Selection
  @Binding var path: NavigationPath
  let home: Selection
  let downloads: Selection
  let search: Selection
  /// Search links push this destination on the home stack instead of selecting
  /// the search tab, for shells without a dedicated search tab.
  let searchDestination: NavDestination?

  func body(content: Content) -> some View {
    content
      .onAppear {
        route(router.pendingDeepLink)
      }
      .onChange(of: router.pendingDeepLink) { _, link in
        route(link)
      }
  }

  private func route(_ link: DeepLink?) {
    guard let link else { return }
    router.pendingDeepLink = nil
    switch link {
    case .book(let bookId):
      routeHome(pushing: .bookDetail(bookId: bookId))
    case .series(let seriesId):
      routeHome(pushing: .seriesDetail(seriesId: seriesId))
    case .search:
      if let searchDestination {
        routeHome(pushing: searchDestination)
      } else {
        selection = search
      }
    case .downloads:
      selection = downloads
    }
  }

  private func routeHome(pushing destination: NavDestination) {
    selection = home
    // Reset and push land in a single path assignment; a deferred append after
    // a reset races the stack rebuild and can silently drop the push.
    var newPath = NavigationPath()
    newPath.append(destination)
    path = newPath
  }
}

extension View {
  func deepLinkRouting<Selection: Equatable>(
    selection: Binding<Selection>,
    path: Binding<NavigationPath>,
    home: Selection,
    downloads: Selection,
    search: Selection? = nil,
    searchDestination: NavDestination? = nil
  ) -> some View {
    modifier(
      DeepLinkRoutingModifier(
        selection: selection,
        path: path,
        home: home,
        downloads: downloads,
        search: search ?? home,
        searchDestination: searchDestination
      )
    )
  }
}
