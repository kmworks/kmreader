//
// SmartListLibraryPickerSheet.swift
//
//

import SwiftUI

struct SmartListLibraryPickerSheet: View {
  let libraries: [LibraryInfo]
  @Binding var selection: Set<String>

  var body: some View {
    SheetView(title: String(localized: "Libraries"), size: .medium, applyFormStyle: true) {
      Form {
        if libraries.isEmpty {
          Text(
            String(localized: "smartlist.libraryPicker.empty", defaultValue: "No libraries.")
          )
          .foregroundStyle(.secondary)
        } else {
          Section {
            ForEach(libraries) { library in
              Button {
                toggle(library.id)
              } label: {
                HStack {
                  Text(library.name)
                  Spacer()
                  if selection.contains(library.id) {
                    Image(systemName: AppIcon.confirm)
                      .foregroundStyle(.tint)
                  }
                }
                .foregroundStyle(.primary)
                .animation(.appCurve(), value: selection.contains(library.id))
              }
            }
          }
        }
      }
    }
  }

  private func toggle(_ id: String) {
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
  }
}
