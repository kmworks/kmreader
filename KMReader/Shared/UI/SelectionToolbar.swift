//
// SelectionToolbar.swift
//
//

import SwiftUI

struct SelectionToolbar: View {
  let selectedCount: Int
  let totalCount: Int
  let isDeleting: Bool
  let onSelectAll: () -> Void
  let onDelete: () -> Void
  let onCancel: () -> Void

  var deleteLabel: String {
    selectedCount == 0
      ? String(localized: "Delete")
      : String(localized: "Delete (\(selectedCount))")
  }

  var submitDisabled: Bool {
    // Full selection stays disabled to intentionally prevent emptying the
    // collection/readlist through the selection UI.
    isDeleting || selectedCount == 0 || selectedCount == totalCount
  }

  var body: some View {
    HStack {
      SelectAllButton(selectedCount: selectedCount, totalCount: totalCount, action: onSelectAll)

      Button(role: .destructive) {
        if selectedCount > 0 {
          onDelete()
        }
      } label: {
        Label(deleteLabel, systemImage: "trash.fill")
          .font(.footnote)
      }
      .adaptiveButtonStyle(.borderedProminent)
      .disabled(submitDisabled)
      .opacity(selectedCount == 0 ? 0 : 1)

      Spacer()

      Button(role: .cancel) {
        withAnimation {
          onCancel()
        }
      } label: {
        Label(String(localized: "Cancel"), systemImage: "xmark.circle")
          .font(.footnote)
      }
      .adaptiveButtonStyle(.bordered)
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}
