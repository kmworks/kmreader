//
// EntityPickerSheet.swift
//
//

import SwiftUI

/// Generic picker sheet for adding a book/series to a named entity (collection,
/// read list): searchable single-selection list with already-member rows
/// disabled, a Create New entry, and a Done confirmation. The caller owns data
/// loading and passes the mapped items in.
struct EntityPickerSheet<CreateSheet: View>: View {
  let title: String
  let emptyText: String
  let icon: String
  let items: [EntityPickerItem]
  let isLoading: Bool
  let onSelect: (String) -> Void
  let createSheet: () -> CreateSheet

  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var selectedItemId: String?
  @State private var searchText: String = ""
  @State private var showCreateSheet = false

  private var filteredItems: [EntityPickerItem] {
    if searchText.isEmpty {
      return items
    }
    return items.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    SheetView(title: title, size: .large, applyFormStyle: true) {
      Form {
        if isLoading && items.isEmpty {
          LoadingIcon()
            .frame(maxWidth: .infinity)
        } else if items.isEmpty {
          Text(emptyText)
            .foregroundColor(.secondary)
        } else if filteredItems.isEmpty {
          ContentUnavailableView.search(text: searchText)
        } else {
          Section {
            ForEach(filteredItems) { item in
              Button {
                if !item.alreadyIn {
                  selectedItemId = item.id
                }
              } label: {
                HStack {
                  Label(item.name, systemImage: icon)
                  Spacer()
                  if item.alreadyIn {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                  } else if selectedItemId == item.id {
                    Image(systemName: "checkmark")
                      .foregroundStyle(.tint)
                  }
                }
                .foregroundStyle(item.alreadyIn ? .secondary : .primary)
                .animation(.appCurve(), value: selectedItemId == item.id)
              }
              .disabled(item.alreadyIn)
            }
          }
        }
      }
    } controls: {
      Button {
        withAnimation {
          showCreateSheet = true
        }
      } label: {
        Label("Create New", systemImage: "plus.circle.fill")
      }
      .disabled(!current.isAdmin)

      HStack(spacing: 12) {
        Button(action: confirmSelection) {
          Label("Done", systemImage: "checkmark")
        }
        .disabled(selectedItemId == nil)
      }
    }
    .searchable(text: $searchText)
    .sheet(isPresented: $showCreateSheet) {
      createSheet()
    }
  }

  private func confirmSelection() {
    if let selectedItemId = selectedItemId {
      onSelect(selectedItemId)
      dismiss()
    }
  }
}
