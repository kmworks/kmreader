//
// View+Navigation.swift
//
//

import SwiftUI

extension View {
  /// Set the navigation title on platforms that show one. Only macOS renders
  /// it (as the window title); iOS and tvOS leave the navigation bar untitled
  /// because tab labels, detail heroes, and section headers already carry page
  /// identity. iOS still pins the inline display mode: `.automatic` reserves
  /// an empty large-title area on stack roots. iPhone tab roots show their
  /// title as an `InlineLargeBarTitle` toolbar item instead.
  func platformNavigationTitle(_ title: String) -> some View {
    #if os(iOS)
      return self.navigationBarTitleDisplayMode(.inline)
    #elseif os(macOS)
      return self.navigationTitle(title)
    #else
      return self
    #endif
  }

  func handleNavigation(context: AppViewContext) -> some View {
    self.modifier(NavigationHandlingModifier(context: context))
  }
}

private struct NavigationHandlingModifier: ViewModifier {
  let context: AppViewContext
  @Environment(\.zoomNamespace) private var zoomNamespace
  @Environment(\.browseLibrarySelection) private var browseLibrarySelection

  func body(content: Content) -> some View {
    content
      .navigationDestination(for: NavDestination.self) { destination in
        destination.content(context: context)
          .environment(\.browseLibrarySelection, destination.librarySelection ?? browseLibrarySelection)
          // Pushed pages keep a page-local session scope; the shell-owned
          // scope binding belongs to the tab/split root that provided it.
          .environment(\.libraryScopeBinding, nil)
          .environment(\.readerActions, context.readerActions)
          .navigationTransitionZoomIfAvailable(sourceID: destination.zoomSourceID, in: zoomNamespace)
      }
  }
}
