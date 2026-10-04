//
// View+FocusableHighlight.swift
//
//

import SwiftUI

#if os(tvOS)
  private struct TVFocusableHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
      content
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(.appCurve(0.15), value: isFocused)
        .focusable()
        .focused($isFocused)
        .listRowBackground(
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(isFocused ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
        )
    }
  }
#endif

extension View {
  /// Adds a default highlight effect for focusable rows on tvOS.
  ///
  /// **Important**: This modifier is designed for NON-INTERACTIVE elements only,
  /// such as plain text rows in a List. Do NOT use this on Buttons, NavigationLinks,
  /// or other interactive elements, as it will interfere with their built-in focus behavior.
  ///
  /// For interactive elements, use their native button styles or custom ButtonStyle instead.
  ///
  /// - Parameter cornerRadius: The corner radius for the highlight shape (default: 12)
  /// - Returns: View with focus highlight on tvOS, unchanged on other platforms
  @ViewBuilder
  func tvFocusableHighlight(cornerRadius: CGFloat = 12) -> some View {
    #if os(tvOS)
      modifier(TVFocusableHighlightModifier(cornerRadius: cornerRadius))
    #else
      self
    #endif
  }
}
