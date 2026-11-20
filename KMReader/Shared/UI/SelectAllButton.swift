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

  private var allSelected: Bool {
    totalCount > 0 && selectedCount == totalCount
  }

  private var label: String {
    allSelected
      ? String(localized: "Deselect All")
      : String(localized: "Select All")
  }

  private var image: String {
    allSelected ? "checkmark.circle.fill" : "checkmark.circle"
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
    .disabled(totalCount == 0)
  }
}
