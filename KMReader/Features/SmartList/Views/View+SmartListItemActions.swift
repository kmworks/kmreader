//
// View+SmartListItemActions.swift
//
//

import SwiftUI

extension View {
  /// Shared edit-sheet and delete-alert wiring for smart list cards and rows;
  /// the flags stay in the caller's state so its context menu can flip them.
  func smartListItemActions(
    smartList: SmartList,
    showEditSheet: Binding<Bool>,
    showDeleteConfirmation: Binding<Bool>
  ) -> some View {
    self
      .sheet(isPresented: showEditSheet) {
        SmartListEditSheet(mode: .edit(smartList))
      }
      .alert("Delete Smart List", isPresented: showDeleteConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Delete", role: .destructive) {
          Task {
            do {
              try await SmartListService.deleteSmartList(smartListId: smartList.id)
              ErrorManager.shared.notify(
                message: String(
                  localized: "notification.smartList.deleted", defaultValue: "Smart list deleted"))
            } catch {
              ErrorManager.shared.alert(error: error)
            }
          }
        }
      } message: {
        Text("Are you sure you want to delete this smart list? This action cannot be undone.")
      }
  }
}
