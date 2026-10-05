//
// SelectionActionsToolbar.swift
//
//

import SwiftUI

/// Selection-mode toolbar for batch actions on the selected items: mark
/// read/unread plus one list-membership action (add to read list/collection).
/// All buttons use circle-family glyphs so the capsules come out the same
/// size; the accessibility label carries each action's meaning.
struct SelectionActionsToolbar: View {
  let selectedCount: Int
  let totalCount: Int
  let isSubmitting: Bool
  let addLabel: String
  let onSelectAll: () -> Void
  let onMarkRead: () -> Void
  let onMarkUnread: () -> Void
  let onAdd: () -> Void
  let onCancel: () -> Void

  var submitDisabled: Bool {
    isSubmitting || selectedCount == 0
  }

  var body: some View {
    HStack(spacing: 12) {
      SelectAllButton(selectedCount: selectedCount, totalCount: totalCount, action: onSelectAll)

      Spacer()

      Button {
        onMarkRead()
      } label: {
        Image(systemName: "checkmark.circle")
      }
      .adaptiveButtonStyle(.bordered)
      .disabled(submitDisabled)
      .accessibilityLabel(String(localized: "Mark Read"))

      Button {
        onMarkUnread()
      } label: {
        Image(systemName: "circle")
      }
      .adaptiveButtonStyle(.bordered)
      .disabled(submitDisabled)
      .accessibilityLabel(String(localized: "Mark Unread"))

      Button {
        onAdd()
      } label: {
        Image(systemName: "plus.circle")
      }
      .adaptiveButtonStyle(.bordered)
      .disabled(submitDisabled)
      .accessibilityLabel(addLabel)

      Button(role: .cancel) {
        withAnimation {
          onCancel()
        }
      } label: {
        Image(systemName: "xmark")
      }
      .adaptiveButtonStyle(.bordered)
      .accessibilityLabel(String(localized: "Cancel"))
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}
