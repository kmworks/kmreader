//
// PanelModeHintView.swift
//
//

import SwiftUI

/// Gesture hint shown over the page while panel mode is new to the reader. It stays until the
/// reader acts on it (a double-tap starts a walk, a tap steps) rather than timing out, and the
/// reader stops showing it after a few walks.
struct PanelModeHintView: View {
  /// Walks after which the hints are no longer shown.
  static let retireAfterWalks = 3

  let isWalking: Bool

  var body: some View {
    Group {
      if isWalking {
        Text("Tap for the next panel · Double-tap for the full page")
      } else {
        Text("Double-tap a panel to zoom in")
      }
    }
    .font(.footnote.weight(.medium))
    .multilineTextAlignment(.center)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial, in: Capsule())
    .allowsHitTesting(false)
  }
}
