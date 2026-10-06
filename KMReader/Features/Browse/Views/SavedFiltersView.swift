//
// SavedFiltersView.swift
//
//

import SwiftUI

struct SavedFiltersView: View {
  @Environment(\.dismiss) private var dismiss

  let filterType: SavedFilterType
  @State private var savedFilters: [SavedFilterDisplayItem] = []
  @State private var filterToRename: SavedFilterDisplayItem?
  @State private var newName: String = ""

  private var isRenameAlertPresented: Binding<Bool> {
    Binding(
      get: { filterToRename != nil },
      set: {
        if !$0 {
          withAnimation {
            filterToRename = nil
          }
        }
      }
    )
  }

  var body: some View {
    SheetView(
      title: String(localized: "Saved Filters"),
      size: .medium,
      applyFormStyle: true
    ) {
      if savedFilters.isEmpty {
        ContentUnavailableView {
          Label("No Saved Filters", systemImage: "bookmark.slash")
        } description: {
          Text(
            "Save your frequently used \(filterType.displayName.lowercased()) filters for quick access"
          )
        }
      } else {
        List {
          Section(filterType.displayName) {
            ForEach(savedFilters) { filter in
              filterRow(filter)
            }
          }
        }
      }
    }
    .alert(
      "Rename Filter",
      isPresented: isRenameAlertPresented
    ) {
      TextField("Filter Name", text: $newName)
      Button("Cancel", role: .cancel) {
        withAnimation {
          filterToRename = nil
          newName = ""
        }
      }
      Button("Rename") {
        if let filter = filterToRename {
          renameFilter(filter, to: newName)
        }
      }
    }
    .task(id: filterType) {
      await loadFilters()
    }
  }

  @ViewBuilder
  private func filterRow(_ filter: SavedFilterDisplayItem) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(filter.name)
          .font(.body)
        Text(filter.updatedAt, style: .relative)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Button {
        applyFilterDirectly(filter)
        dismiss()
      } label: {
        Image(systemName: "arrowshape.turn.up.forward")
          .foregroundColor(.primary)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .adaptiveButtonStyle(.plain)
      .accessibilityLabel(Text("Apply Filter"))
    }
    #if os(iOS) || os(macOS)
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
          deleteFilter(filter)
        } label: {
          Label("Delete", systemImage: AppIcon.delete)
        }

        Button {
          withAnimation {
            newName = filter.name
            filterToRename = filter
          }
        } label: {
          Label("Rename", systemImage: AppIcon.edit)
        }
      }
    #endif
    .contextMenu {
      Button {
        applyFilterDirectly(filter)
        dismiss()
      } label: {
        Label("Apply Filter", systemImage: "arrowshape.turn.up.forward")
      }

      Button {
        withAnimation {
          newName = filter.name
          filterToRename = filter
        }
      } label: {
        Label("Rename", systemImage: AppIcon.edit)
      }

      Divider()

      Button(role: .destructive) {
        deleteFilter(filter)
      } label: {
        Label("Delete", systemImage: AppIcon.delete)
      }
    }
  }

  private func applyFilterDirectly(_ filter: SavedFilterDisplayItem) {
    switch filter.filterType {
    case .series:
      if let options = SeriesBrowseOptions(rawValue: filter.filterDataJSON) {
        AppConfig.seriesBrowseOptions = options.rawValue
      }
    case .books:
      if let options = BookBrowseOptions(rawValue: filter.filterDataJSON) {
        AppConfig.bookBrowseOptions = options.rawValue
      }
    case .collectionSeries:
      if let options = CollectionSeriesBrowseOptions(rawValue: filter.filterDataJSON) {
        AppConfig.collectionSeriesBrowseOptions = options.rawValue
      }
    case .readListBooks:
      if let options = ReadListBookBrowseOptions(rawValue: filter.filterDataJSON) {
        AppConfig.readListBookBrowseOptions = options.rawValue
      }
    case .seriesBooks:
      if let options = BookBrowseOptions(rawValue: filter.filterDataJSON) {
        AppConfig.seriesBookBrowseOptions = options.rawValue
      }
    }
  }

  private func deleteFilter(_ filter: SavedFilterDisplayItem) {
    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await database.deleteSavedFilter(id: filter.id)
        await loadFilters()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func renameFilter(_ filter: SavedFilterDisplayItem, to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await database.renameSavedFilter(id: filter.id, name: trimmed)
        await loadFilters()
        withAnimation {
          filterToRename = nil
          self.newName = ""
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func loadFilters() async {
    do {
      let database = try await DatabaseOperator.database()
      let loadedFilters = try await database.fetchSavedFilterDisplayItems(filterType: filterType)
      if savedFilters != loadedFilters {
        withAnimation {
          savedFilters = loadedFilters
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
