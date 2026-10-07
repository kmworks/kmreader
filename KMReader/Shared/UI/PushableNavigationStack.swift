//
// PushableNavigationStack.swift
//
//

import SwiftUI

/// NavigationStack that publishes a `pushNavDestination` action into the
/// environment, letting deep views push a `NavDestination` value without
/// owning the path. Stacks with an externally owned path keep it; others get
/// one here.
struct PushableNavigationStack<Root: View>: View {
  @State private var ownedPath = NavigationPath()

  let path: Binding<NavigationPath>?
  @ViewBuilder let root: () -> Root

  init(path: Binding<NavigationPath>? = nil, @ViewBuilder root: @escaping () -> Root) {
    self.path = path
    self.root = root
  }

  private var effectivePath: Binding<NavigationPath> {
    path ?? $ownedPath
  }

  var body: some View {
    NavigationStack(path: effectivePath) {
      root()
        .environment(\.pushNavDestination) { destination in
          effectivePath.wrappedValue.append(destination)
        }
    }
  }
}
