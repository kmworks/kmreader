//
// SeriesReadingActionButton.swift
//
//

import SwiftUI

/// Inline primary continue-reading action shown below the series header block.
/// Rendered on every platform except iPhone on iOS 26.1+, where the system
/// tab bar bottom accessory takes over. The button spans the action card's
/// full width.
struct SeriesReadingActionButton: View {
  let caption: String
  let title: String
  let isResolving: Bool
  let action: () -> Void

  var body: some View {
    ReadingActionButton(
      label: caption,
      detail: Text(title),
      isResolving: isResolving,
      action: action
    )
  }
}
