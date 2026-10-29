//
// TrackerLibrarySelectionView.swift
//

import SwiftUI

struct TrackerLibrarySelectionView: View {
  let libraries: [LibraryInfo]
  @Binding var selectedIds: Set<String>

  var body: some View {
    List {
      Section {
        ForEach(libraries) { library in
          Button {
            toggle(library.id)
          } label: {
            HStack {
              Text(library.name)
              Spacer()
              if selectedIds.contains(library.id) {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
            .contentShape(Rectangle())
          }
          .adaptiveButtonStyle(.plain)
        }
      } footer: {
        Text(String(localized: "With no libraries selected, tracker actions are available everywhere."))
      }
    }
    .platformNavigationTitle(String(localized: "Libraries"))
  }

  private func toggle(_ id: String) {
    if selectedIds.contains(id) {
      selectedIds.remove(id)
    } else {
      selectedIds.insert(id)
    }
  }
}
