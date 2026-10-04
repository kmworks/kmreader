//
// SelectAllButton.swift
//
//

import SwiftUI

/// Select All / Deselect All toggle for selection-mode toolbars.
struct SelectAllButton: View {
  let selectedCount: Int
  let totalCount: Int
  let action: () -> Void

  private var label: String {
    selectedCount == totalCount
      ? String(localized: "Deselect All")
      : String(localized: "Select All")
  }

  private var image: String {
    selectedCount == totalCount ? "checkmark.circle.fill" : "checkmark.circle"
  }

  var body: some View {
    Button {
      withAnimation {
        action()
      }
    } label: {
      Label(label, systemImage: image)
        .font(.footnote)
    }
    .adaptiveButtonStyle(.bordered)
  }
}
