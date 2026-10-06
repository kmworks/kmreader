//
// CollectionEditSheet.swift
//
//

import SwiftUI

struct CollectionEditSheet: View {
  let collection: SeriesCollection
  @Environment(\.dismiss) private var dismiss
  @State private var isSaving = false

  @State private var name: String
  @State private var ordered: Bool

  init(collection: SeriesCollection) {
    self.collection = collection
    _name = State(initialValue: collection.name)
    _ordered = State(initialValue: collection.ordered)
  }

  var body: some View {
    SheetView(title: String(localized: "Edit Collection"), size: .medium, applyFormStyle: true) {
      Form {
        Section("Basic Information") {
          TextField("Name", text: $name)
          Toggle("Ordered", isOn: $ordered)
        }
      }
    } controls: {
      Button(action: saveChanges) {
        if isSaving {
          ProgressView()
        } else {
          Label("Save", systemImage: AppIcon.confirm)
        }
      }
      .disabled(isSaving || name.isEmpty)
    }
  }

  private func saveChanges() {
    isSaving = true
    Task {
      do {
        var hasChanges = false
        var nameToUpdate: String? = nil
        var orderedToUpdate: Bool? = nil

        if name != collection.name {
          nameToUpdate = name
          hasChanges = true
        }
        if ordered != collection.ordered {
          orderedToUpdate = ordered
          hasChanges = true
        }

        if hasChanges {
          try await CollectionService.updateCollection(
            collectionId: collection.id,
            name: nameToUpdate,
            ordered: orderedToUpdate
          )
          ErrorManager.shared.notify(
            message: String(localized: "notification.collection.updated"))
          dismiss()
        } else {
          dismiss()
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSaving = false
    }
  }
}
