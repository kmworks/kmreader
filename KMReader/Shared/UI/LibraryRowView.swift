//
// LibraryRowView.swift
//
//

import SwiftUI

struct LibraryRowView: View {
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()
  let library: SidebarLibraryItem
  let selectionEnabled: Bool
  let isSingleSelectionMode: Bool
  let isSelected: Bool
  let onSelect: (() -> Void)?
  let onAction: (LibraryAction) -> Void
  let onEdit: (() -> Void)?
  let onDelete: (() -> Void)?

  init(
    library: SidebarLibraryItem,
    selectionEnabled: Bool = false,
    isSingleSelectionMode: Bool = false,
    isSelected: Bool,
    onSelect: (() -> Void)? = nil,
    onAction: @escaping (LibraryAction) -> Void,
    onEdit: (() -> Void)? = nil,
    onDelete: (() -> Void)? = nil
  ) {
    self.library = library
    self.selectionEnabled = selectionEnabled
    self.isSingleSelectionMode = isSingleSelectionMode
    self.isSelected = isSelected
    self.onSelect = onSelect
    self.onAction = onAction
    self.onEdit = onEdit
    self.onDelete = onDelete
  }

  var body: some View {
    let rowContent = HStack(spacing: 12) {
      LibraryRowTextContent(
        name: library.name,
        fileSize: library.fileSize,
        metricsText: LibraryMetricsText.metrics(for: library)
      )

      Spacer()

      if selectionEnabled {
        LibrarySelectionIndicator(
          isSelected: isSelected,
          isSingleSelectionMode: isSingleSelectionMode
        )
      }
    }
    .contentShape(Rectangle())

    Group {
      if let onSelect {
        Button {
          onSelect()
        } label: {
          rowContent
        }
        .buttonStyle(.plain)
      } else {
        rowContent
      }
    }
    .contextMenu {
      if current.isAdmin && !isOffline {
        if let onEdit {
          Button {
            onEdit()
          } label: {
            Label(
              String(localized: "library.action.edit", defaultValue: "Edit Library"),
              systemImage: "pencil")
          }

          Divider()
        }

        ForEach(LibraryAction.allCases, id: \.self) { action in
          Button {
            onAction(action)
          } label: {
            action.label
          }
        }

        if let onDelete {
          Divider()

          Button(role: .destructive) {
            onDelete()
          } label: {
            Label(String(localized: "Delete Library"), systemImage: "trash")
          }
        }
      }
    }
  }
}
