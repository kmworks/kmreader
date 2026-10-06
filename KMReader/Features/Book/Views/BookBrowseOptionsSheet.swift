//
// BookBrowseOptionsSheet.swift
//
//

import SwiftUI

struct BookBrowseOptionsSheet: View {
  @Binding var browseOpts: BookBrowseOptions
  @Environment(\.dismiss) private var dismiss
  @State private var tempOpts: BookBrowseOptions
  @State private var showSaveFilterSheet = false
  let filterType: SavedFilterType
  let seriesId: String?
  let libraryIds: [String]?
  let includeOfflineSorts: Bool
  let usesRelevanceSort: Bool
  let ignoresFiltersForSearch: Bool

  private var availableSortFields: [BookSortField] {
    includeOfflineSorts ? BookSortField.offlineCases : BookSortField.onlineCases
  }

  private var defaultOptions: BookBrowseOptions {
    var options = BookBrowseOptions()
    if includeOfflineSorts {
      options.sortField = .downloadDate
      options.sortDirection = .descending
    }
    if !availableSortFields.contains(options.sortField), let fallbackField = availableSortFields.first {
      options.sortField = fallbackField
    }
    return options
  }

  init(
    browseOpts: Binding<BookBrowseOptions>,
    filterType: SavedFilterType = .books,
    seriesId: String? = nil,
    libraryIds: [String]? = nil,
    includeOfflineSorts: Bool = false,
    usesRelevanceSort: Bool = false,
    ignoresFiltersForSearch: Bool = false
  ) {
    var initialOpts = browseOpts.wrappedValue
    let availableSortFields = includeOfflineSorts ? BookSortField.offlineCases : BookSortField.onlineCases
    if !availableSortFields.contains(initialOpts.sortField), let fallbackField = availableSortFields.first {
      initialOpts.sortField = fallbackField
    }

    self._browseOpts = browseOpts
    self._tempOpts = State(initialValue: initialOpts)
    self.filterType = filterType
    self.seriesId = seriesId
    self.libraryIds = libraryIds
    self.includeOfflineSorts = includeOfflineSorts
    self.usesRelevanceSort = usesRelevanceSort
    self.ignoresFiltersForSearch = ignoresFiltersForSearch
  }

  var body: some View {
    SheetView(
      title: String(localized: "Filter & Sort"), size: .both, onReset: resetOptions,
      applyFormStyle: true
    ) {
      Form {
        sortSection
        ignoredFiltersSection

        Section(String(localized: "Read Status")) {
          ForEach(ReadStatus.allCases, id: \.self) { filter in
            Button {
              toggleReadStatus(filter)
            } label: {
              HStack {
                Text(filter.displayName)
                Spacer()
                let state = resolveReadStatusState(
                  for: filter,
                  include: tempOpts.includeReadStatuses,
                  exclude: tempOpts.excludeReadStatuses
                )
                Image(systemName: state.iconName)
                  .foregroundStyle(state.color)
                  .animation(.appCurve(), value: state)
              }
            }
          }
        }

        Section(String(localized: "Flags")) {
          Button {
            tempOpts.oneshotFilter.cycle(to: .yes)
          } label: {
            HStack {
              Text(FilterStrings.oneshot)
              Spacer()
              let state = tempOpts.oneshotFilter.state(for: .yes)
              Image(systemName: state.iconName)
                .foregroundStyle(state.color)
                .animation(.appCurve(), value: state)
            }
          }

          Button {
            tempOpts.deletedFilter.cycle(to: .yes)
          } label: {
            HStack {
              Text(FilterStrings.deleted)
              Spacer()
              let state = tempOpts.deletedFilter.state(for: .yes)
              Image(systemName: state.iconName)
                .foregroundStyle(state.color)
                .animation(.appCurve(), value: state)
            }
          }
        }

        MetadataFilterSection(
          metadataFilter: $tempOpts.metadataFilter,
          libraryIds: libraryIds,
          seriesId: seriesId,
          showAuthors: true,
          showTags: true
        )

      }
    } controls: {
      Button {
        withAnimation {
          showSaveFilterSheet = true
        }
      } label: {
        Label(String(localized: "Save Filter"), systemImage: "bookmark")
      }
      Button(action: applyChanges) {
        Label(String(localized: "Done"), systemImage: AppIcon.confirm)
      }
    }
    .sheet(isPresented: $showSaveFilterSheet) {
      SaveFilterSheet(
        filterType: filterType,
        bookOptions: tempOpts
      )
    }
  }

  @ViewBuilder
  private var ignoredFiltersSection: some View {
    if ignoresFiltersForSearch {
      Section(String(localized: "Filters")) {
        Label(String(localized: "filters.ignored"), systemImage: AppIcon.filterCircle)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var sortSection: some View {
    if usesRelevanceSort {
      Section(String(localized: "Sort")) {
        Label(String(localized: "sort.relevance"), systemImage: AppIcon.search)
          .foregroundStyle(.secondary)
      }
    } else {
      SortOptionView(
        sortField: $tempOpts.sortField,
        sortDirection: $tempOpts.sortDirection,
        sortFields: availableSortFields
      )
    }
  }

  private func resetOptions() {
    withAnimation {
      let sortField = tempOpts.sortField
      let sortDirection = tempOpts.sortDirection
      tempOpts = defaultOptions
      if usesRelevanceSort {
        tempOpts.sortField = sortField
        tempOpts.sortDirection = sortDirection
      }
    }
  }

  private func applyChanges() {
    if tempOpts != browseOpts {
      browseOpts = tempOpts
    }
    dismiss()
  }

  private func state(for status: ReadStatus) -> TriStateSelection {
    if tempOpts.includeReadStatuses.contains(status) {
      return .include
    }
    if tempOpts.excludeReadStatuses.contains(status) {
      return .exclude
    }
    return .off
  }

  private func toggleReadStatus(_ status: ReadStatus) {
    var include = tempOpts.includeReadStatuses
    var exclude = tempOpts.excludeReadStatuses
    KMReader.applyReadStatusToggle(status, include: &include, exclude: &exclude)
    tempOpts.includeReadStatuses = include
    tempOpts.excludeReadStatuses = exclude
  }
}
