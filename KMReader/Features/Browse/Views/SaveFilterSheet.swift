//
// SaveFilterSheet.swift
//
//

import SwiftUI

struct SaveFilterSheet: View {
  @Environment(\.dismiss) private var dismiss

  let filterType: SavedFilterType
  let seriesOptions: SeriesBrowseOptions?
  let bookOptions: BookBrowseOptions?
  let collectionOptions: CollectionSeriesBrowseOptions?
  let readListOptions: ReadListBookBrowseOptions?

  @State private var filterName: String = ""
  @State private var isSaving: Bool = false

  init(
    filterType: SavedFilterType,
    seriesOptions: SeriesBrowseOptions? = nil,
    bookOptions: BookBrowseOptions? = nil,
    collectionOptions: CollectionSeriesBrowseOptions? = nil,
    readListOptions: ReadListBookBrowseOptions? = nil
  ) {
    self.filterType = filterType
    self.seriesOptions = seriesOptions
    self.bookOptions = bookOptions
    self.collectionOptions = collectionOptions
    self.readListOptions = readListOptions
  }

  var body: some View {
    SheetView(
      title: String(localized: "Save Filter"),
      size: .medium,
      applyFormStyle: true
    ) {
      Form {
        Section {
          TextField("Filter Name", text: $filterName)
            .textFieldStyle(.plain)
        } header: {
          Text("Name")
        }

        Section {
          LabeledContent("Type", value: filterType.displayName)
        }
      }

    } controls: {
      Button(action: saveFilter) {
        if isSaving {
          ProgressView()
        } else {
          Label("Save Filter", systemImage: AppIcon.confirm)
        }
      }
      .disabled(filterName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
    }
  }

  func saveFilter() {
    let trimmedName = filterName.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { return }

    isSaving = true

    guard let filterDataJSON else {
      ErrorManager.shared.alert(message: "Failed to create filter")
      isSaving = false
      return
    }

    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await database.createSavedFilter(
          name: trimmedName,
          filterType: filterType,
          filterDataJSON: filterDataJSON
        )
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
        isSaving = false
      }
    }
  }

  private var filterDataJSON: String? {
    switch filterType {
    case .series:
      return seriesOptions?.rawValue
    case .books, .seriesBooks:
      return bookOptions?.rawValue
    case .collectionSeries:
      return collectionOptions?.rawValue
    case .readListBooks:
      return readListOptions?.rawValue
    }
  }
}
