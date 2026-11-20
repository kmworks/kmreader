//
// SelectionActionsToolbar.swift
//
//

import SwiftUI

/// Selection-mode toolbar for common read-state actions and a More menu that
/// mirrors the batch operations exposed by kmweb.
struct SelectionActionsToolbar: View {
  let selectedCount: Int
  let totalCount: Int
  let isSubmitting: Bool
  let completedCount: Int
  let runningTotalCount: Int
  let addLabel: String
  let editLabel: String
  let deleteLabel: String?
  let komfMatchLabel: String?
  let onSelectAll: () -> Void
  let onMarkRead: () -> Void
  let onMarkUnread: () -> Void
  let onAdd: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onKomfMatch: () -> Void
  let onCancel: () -> Void

  var submitDisabled: Bool {
    isSubmitting || selectedCount == 0
  }

  var body: some View {
    HStack(spacing: 12) {
      if isSubmitting {
        ProgressView()
          .controlSize(.small)
        Text("batch.progress \(completedCount) \(runningTotalCount)")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        Spacer()
      } else {
        SelectAllButton(selectedCount: selectedCount, totalCount: totalCount, action: onSelectAll)

        Spacer()

        Button {
          onMarkRead()
        } label: {
          Image(systemName: "checkmark.circle")
        }
        .adaptiveButtonStyle(.bordered)
        .optimizedControlSize()
        .disabled(submitDisabled)
        .accessibilityLabel(String(localized: "Mark Read"))

        Button {
          onMarkUnread()
        } label: {
          Image(systemName: "circle")
        }
        .adaptiveButtonStyle(.bordered)
        .optimizedControlSize()
        .disabled(submitDisabled)
        .accessibilityLabel(String(localized: "Mark Unread"))

        Menu {
          Button {
            onAdd()
          } label: {
            Label(addLabel, systemImage: AppIcon.addRow)
          }

          Button {
            onEdit()
          } label: {
            Label(editLabel, systemImage: AppIcon.edit)
          }

          if let komfMatchLabel {
            Button {
              onKomfMatch()
            } label: {
              Label(komfMatchLabel, systemImage: "arrow.triangle.2.circlepath")
            }
          }

          if let deleteLabel {
            Divider()
            Button(role: .destructive) {
              onDelete()
            } label: {
              Label(deleteLabel, systemImage: AppIcon.delete)
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .adaptiveButtonStyle(.bordered)
        .optimizedControlSize()
        .disabled(submitDisabled)
        .accessibilityLabel(String(localized: "More Actions"))

        Button(role: .cancel) {
          withAnimation {
            onCancel()
          }
        } label: {
          Image(systemName: "xmark.circle")
        }
        .adaptiveButtonStyle(.bordered)
        .optimizedControlSize()
        .accessibilityLabel(String(localized: "Cancel"))
      }
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}
