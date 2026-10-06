//
// ReadListEditSheet.swift
//
//

import SwiftUI

struct ReadListEditSheet: View {
  let readList: ReadList
  @Environment(\.dismiss) private var dismiss
  @State private var isSaving = false

  @State private var name: String
  @State private var summary: String
  @State private var ordered: Bool

  init(readList: ReadList) {
    self.readList = readList
    _name = State(initialValue: readList.name)
    _summary = State(initialValue: readList.summary)
    _ordered = State(initialValue: readList.ordered)
  }

  var body: some View {
    SheetView(title: String(localized: "Edit Read List"), size: .medium, applyFormStyle: true) {
      Form {
        Section("Basic Information") {
          TextField("Name", text: $name)
          TextField("Summary", text: $summary, axis: .vertical)
            .lineLimit(3...10)
          Toggle("Ordered", isOn: $ordered)
        }
      }
    } controls: {
      Button(action: saveChanges) {
        if isSaving {
          LoadingIcon()
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
        var summaryToUpdate: String? = nil
        var orderedToUpdate: Bool? = nil

        if name != readList.name {
          nameToUpdate = name
          hasChanges = true
        }
        if summary != readList.summary {
          summaryToUpdate = summary
          hasChanges = true
        }
        if ordered != readList.ordered {
          orderedToUpdate = ordered
          hasChanges = true
        }

        if hasChanges {
          try await ReadListService.updateReadList(
            readListId: readList.id,
            name: nameToUpdate,
            summary: summaryToUpdate,
            ordered: orderedToUpdate
          )
          ErrorManager.shared.notify(message: String(localized: "notification.readList.updated"))
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
