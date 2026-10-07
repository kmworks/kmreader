//
// SeriesBrowseOptionsSheet.swift
//
//

import SwiftUI

struct SeriesBrowseOptionsSheet: View {
  @Binding var browseOpts: SeriesBrowseOptions
  @Environment(\.dismiss) private var dismiss
  @State private var tempOpts: SeriesBrowseOptions
  @State private var showSaveFilterSheet = false
  let libraryIds: [String]?
  let includeOfflineSorts: Bool
  let usesRelevanceSort: Bool
  let ignoresFiltersForSearch: Bool
  /// Smart lists store no sort (chosen at browse time); hiding sort also hides
  /// Save Filter, since presets write the shared browse-options keys.
  let showsSort: Bool

  private var availableSortFields: [SeriesSortField] {
    includeOfflineSorts ? SeriesSortField.offlineCases : SeriesSortField.onlineCases
  }

  private var defaultOptions: SeriesBrowseOptions {
    var options = SeriesBrowseOptions()
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
    browseOpts: Binding<SeriesBrowseOptions>,
    libraryIds: [String]? = nil,
    includeOfflineSorts: Bool = false,
    usesRelevanceSort: Bool = false,
    ignoresFiltersForSearch: Bool = false,
    showsSort: Bool = true
  ) {
    var initialOpts = browseOpts.wrappedValue
    let availableSortFields = includeOfflineSorts ? SeriesSortField.offlineCases : SeriesSortField.onlineCases
    if !availableSortFields.contains(initialOpts.sortField), let fallbackField = availableSortFields.first {
      initialOpts.sortField = fallbackField
    }

    self._browseOpts = browseOpts
    self._tempOpts = State(initialValue: initialOpts)
    self.libraryIds = libraryIds
    self.includeOfflineSorts = includeOfflineSorts
    self.usesRelevanceSort = usesRelevanceSort
    self.ignoresFiltersForSearch = ignoresFiltersForSearch
    self.showsSort = showsSort
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

        Section(String(localized: "Series Status")) {
          Picker(String(localized: "Logic"), selection: $tempOpts.seriesStatusLogic) {
            Text(String(localized: "All")).tag(FilterLogic.all)
            Text(String(localized: "Any")).tag(FilterLogic.any)
          }
          .pickerStyle(.segmented)

          ForEach(SeriesStatus.allCases, id: \.self) { filter in
            Button {
              cycleSeriesStatus(filter)
            } label: {
              HStack {
                Text(filter.displayName)
                Spacer()
                let state = state(for: filter)
                Image(systemName: state.iconName)
                  .foregroundStyle(state.color)
                  .animation(.appCurve(), value: state)
              }
            }
          }
        }

        Section(String(localized: "Flags")) {
          Button {
            tempOpts.completeFilter.cycle(to: .yes)
          } label: {
            HStack {
              Text(FilterStrings.complete)
              Spacer()
              let state = tempOpts.completeFilter.state(for: .yes)
              Image(systemName: state.iconName)
                .foregroundStyle(state.color)
                .animation(.appCurve(), value: state)
            }
          }

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
          showPublisher: true,
          showAuthors: true,
          showGenres: true,
          showTags: true,
          showLanguages: true,
          showAgeRatings: true,
          showReleaseYears: true
        )

      }
    } controls: {
      if showsSort {
        Button {
          withAnimation {
            showSaveFilterSheet = true
          }
        } label: {
          Label(String(localized: "Save Filter"), systemImage: "bookmark")
        }
      }
      Button(action: applyChanges) {
        Label(String(localized: "Done"), systemImage: AppIcon.confirm)
      }
    }
    .sheet(isPresented: $showSaveFilterSheet) {
      SaveFilterSheet(
        filterType: .series,
        seriesOptions: tempOpts
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
    if showsSort {
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

  private func state(for status: SeriesStatus) -> TriStateSelection {
    if tempOpts.includeSeriesStatuses.contains(status) {
      return .include
    }
    if tempOpts.excludeSeriesStatuses.contains(status) {
      return .exclude
    }
    return .off
  }

  private func cycleSeriesStatus(_ status: SeriesStatus) {
    if tempOpts.includeSeriesStatuses.contains(status) {
      tempOpts.includeSeriesStatuses.remove(status)
      tempOpts.excludeSeriesStatuses.insert(status)
    } else if tempOpts.excludeSeriesStatuses.contains(status) {
      tempOpts.excludeSeriesStatuses.remove(status)
    } else {
      tempOpts.includeSeriesStatuses.insert(status)
    }
  }
}
