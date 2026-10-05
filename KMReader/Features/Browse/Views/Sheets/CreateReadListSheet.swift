//
// CreateReadListSheet.swift
//
//

import SwiftUI

struct CreateReadListSheet: View {
  @Environment(\.dismiss) private var dismiss
  let bookIds: [String]
  let onCreate: (String) -> Void

  @State private var name: String = ""
  @State private var summary: String = ""
  @State private var isCreating = false

  var body: some View {
    SheetView(title: String(localized: "Create Read List"), size: .medium, applyFormStyle: true) {
      Form {
        Section {
          TextField("Read List Name", text: $name)
          TextField("Summary (Optional)", text: $summary, axis: .vertical)
            .lineLimit(3...6)
        }
      }
    } controls: {
      Button(action: createReadList) {
        if isCreating {
          LoadingIcon()
        } else {
          Label("Create", systemImage: "checkmark")
        }
      }
      .disabled(name.isEmpty || isCreating)
    }
  }

  private func createReadList() {
    guard !name.isEmpty else { return }

    withAnimation {
      isCreating = true
    }

    Task {
      do {
        let readList = try await ReadListService.createReadList(
          name: name,
          summary: summary,
          bookIds: bookIds
        )
        // Sync the readlist to update its local book IDs
        _ = try? await SyncService.syncReadList(id: readList.id)
        ErrorManager.shared.notify(message: String(localized: "notification.readList.created"))
        withAnimation {
          isCreating = false
        }
        onCreate(readList.id)
        dismiss()
      } catch {
        withAnimation {
          isCreating = false
        }
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
