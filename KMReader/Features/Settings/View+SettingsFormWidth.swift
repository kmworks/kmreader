//
// View+SettingsFormWidth.swift
//
//

import SwiftUI

extension View {
  /// Caps a settings form at a readable width on iPad and macOS, centered with
  /// at least 16pt of side inset. iPhone and tvOS keep the full-width form.
  @MainActor
  @ViewBuilder
  func settingsFormWidth() -> some View {
    #if os(macOS)
      self.modifier(SettingsFormWidthModifier())
    #elseif os(iOS)
      if PlatformHelper.isPad {
        self.modifier(SettingsFormWidthModifier())
      } else {
        self
      }
    #else
      self
    #endif
  }
}

private struct SettingsFormWidthModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .frame(maxWidth: 674)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
  }
}
