//
// CreateCollectionSheet.swift
//
//

import SwiftUI

struct CreateCollectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  let seriesIds: [String]
  let onCreate: (String) -> Void

  @State private var name: String = ""
  @State private var isCreating = false

  var body: some View {
    SheetView(title: String(localized: "Create Collection"), size: .medium, applyFormStyle: true) {
      Form {
        Section {
          TextField("Collection Name", text: $name)
        }
      }
    } controls: {
      Button(action: createCollection) {
        if isCreating {
          LoadingIcon()
        } else {
          Label("Create", systemImage: "checkmark")
        }
      }
      .disabled(name.isEmpty || isCreating)
    }
  }

  private func createCollection() {
    guard !name.isEmpty else { return }

    withAnimation {
      isCreating = true
    }

    Task {
      do {
        let collection = try await CollectionService.createCollection(
          name: name,
          seriesIds: seriesIds
        )
        // Sync the collection to update its local series IDs
        _ = try? await SyncService.syncCollection(id: collection.id)
        ErrorManager.shared.notify(message: String(localized: "notification.collection.created"))
        withAnimation {
          isCreating = false
        }
        onCreate(collection.id)
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
