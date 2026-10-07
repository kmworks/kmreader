//
// PushNavDestinationKey.swift
//
//

import SwiftUI

private struct PushNavDestinationKey: EnvironmentKey {
  static let defaultValue: (NavDestination) -> Void = { _ in }
}

extension EnvironmentValues {
  /// Pushes a destination onto the enclosing navigation stack, resolving it
  /// through the same `navigationDestination(for:)` mapping the header links
  /// use. Set by `PushableNavigationStack`; the default is a no-op, so views
  /// in unwired stacks (sheets) degrade silently.
  var pushNavDestination: (NavDestination) -> Void {
    get { self[PushNavDestinationKey.self] }
    set { self[PushNavDestinationKey.self] = newValue }
  }
}
