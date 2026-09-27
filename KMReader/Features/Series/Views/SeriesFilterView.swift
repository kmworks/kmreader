//
// SeriesFilterView.swift
//
//

import SwiftUI

struct SeriesFilterView: View {
  @Binding var browseOpts: SeriesBrowseOptions
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool
  let libraryIds: [String]?
  let includeOfflineSorts: Bool
  let usesRelevanceSort: Bool
  let ignoresFiltersForSearch: Bool
  let layoutMode: Binding<BrowseLayoutMode>?

  init(
    browseOpts: Binding<SeriesBrowseOptions>,
    showFilterSheet: Binding<Bool>,
    showSavedFilters: Binding<Bool>,
    libraryIds: [String]? = nil,
    includeOfflineSorts: Bool = false,
    usesRelevanceSort: Bool = false,
    ignoresFiltersForSearch: Bool = false,
    layoutMode: Binding<BrowseLayoutMode>? = nil
  ) {
    self._browseOpts = browseOpts
    self._showFilterSheet = showFilterSheet
    self._showSavedFilters = showSavedFilters
    self.libraryIds = libraryIds
    self.includeOfflineSorts = includeOfflineSorts
    self.usesRelevanceSort = usesRelevanceSort
    self.ignoresFiltersForSearch = ignoresFiltersForSearch
    self.layoutMode = layoutMode
  }

  var sortString: String {
    if usesRelevanceSort {
      return String(localized: "sort.relevance")
    }
    return
      "\(browseOpts.sortField.displayName) \(browseOpts.sortDirection == .ascending ? "↑" : "↓")"
  }

  private var sortIcon: String {
    usesRelevanceSort ? "magnifyingglass" : "arrow.up.arrow.down"
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        if let layoutMode {
          LayoutModeMenu(selection: layoutMode)
        }

        FilterChip(
          label: String(localized: "Presets"),
          systemImage: "bookmark",
          variant: .preset,
          isEnabled: !ignoresFiltersForSearch,
          openSheet: $showSavedFilters
        )

        FilterChip(
          label: sortString,
          systemImage: sortIcon,
          openSheet: $showFilterSheet
        )

        filterChips

      }
      .padding(4)
    }
    .scrollClipDisabled()
    .sheet(isPresented: $showFilterSheet) {
      SeriesBrowseOptionsSheet(
        browseOpts: $browseOpts,
        libraryIds: libraryIds,
        includeOfflineSorts: includeOfflineSorts,
        usesRelevanceSort: usesRelevanceSort,
        ignoresFiltersForSearch: ignoresFiltersForSearch
      )
    }
  }

  @ViewBuilder
  private var filterChips: some View {
    if ignoresFiltersForSearch {
      FilterChip(
        label: String(localized: "filters.ignored"),
        systemImage: "line.3.horizontal.decrease.circle",
        openSheet: $showFilterSheet
      )
    } else {
      if let readLabel = readStatusLabel() {
        FilterChip(
          label: readLabel,
          systemImage: "eye",
          variant: readLabel.contains("≠") ? .negative : .normal,
          openSheet: $showFilterSheet
        )
      }

      if let statusLabel = seriesStatusLabel() {
        FilterChip(
          label: statusLabel.label,
          systemImage: "chart.bar",
          variant: statusLabel.variant,
          openSheet: $showFilterSheet
        )
      }

      if browseOpts.oneshotFilter.isActive,
        let label = browseOpts.oneshotFilter.displayLabel(using: { _ in FilterStrings.oneshot })
      {
        FilterChip(
          label: label,
          systemImage: "dot.circle",
          variant: browseOpts.oneshotFilter.state == .exclude ? .negative : .normal,
          openSheet: $showFilterSheet
        )
      }

      if browseOpts.deletedFilter.isActive,
        let label = browseOpts.deletedFilter.displayLabel(using: { _ in FilterStrings.deleted })
      {
        FilterChip(
          label: label,
          systemImage: "trash",
          variant: browseOpts.deletedFilter.state == .exclude ? .negative : .normal,
          openSheet: $showFilterSheet
        )
      }

      if let publishers = browseOpts.metadataFilter.publishers, !publishers.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.publishersLogic == .all ? "∧" : "∨"
        let label = publishers.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "building.2",
          openSheet: $showFilterSheet
        )
      }

      if let authors = browseOpts.metadataFilter.authors, !authors.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.authorsLogic == .all ? "∧" : "∨"
        let label = authors.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "person",
          openSheet: $showFilterSheet
        )
      }

      if let genres = browseOpts.metadataFilter.genres, !genres.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.genresLogic == .all ? "∧" : "∨"
        let label = genres.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "theatermasks",
          openSheet: $showFilterSheet
        )
      }

      if let tags = browseOpts.metadataFilter.tags, !tags.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.tagsLogic == .all ? "∧" : "∨"
        let label = tags.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "tag",
          openSheet: $showFilterSheet
        )
      }

      if let languages = browseOpts.metadataFilter.languages, !languages.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.languagesLogic == .all ? "∧" : "∨"
        let displayNames = languages.map { LanguageCodeHelper.displayName(for: $0) }
        let label = displayNames.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "globe",
          openSheet: $showFilterSheet
        )
      }

      if let ageRatings = browseOpts.metadataFilter.ageRatings, !ageRatings.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.ageRatingsLogic == .all ? "∧" : "∨"
        let label = ageRatings.map { "\($0)+" }.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "lock",
          openSheet: $showFilterSheet
        )
      }

      if let releaseYears = browseOpts.metadataFilter.releaseYears, !releaseYears.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.releaseYearsLogic == .all ? "∧" : "∨"
        let label = releaseYears.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "calendar",
          openSheet: $showFilterSheet
        )
      }
    }
  }
}

extension SeriesFilterView {
  fileprivate func readStatusLabel() -> String? {
    buildReadStatusLabel(
      include: browseOpts.includeReadStatuses,
      exclude: browseOpts.excludeReadStatuses
    )
  }

  fileprivate func seriesStatusLabel() -> (label: String, variant: FilterChipVariant)? {
    let includeNames = browseOpts.includeSeriesStatuses
      .map { $0.displayName }
      .sorted()
    let excludeNames = browseOpts.excludeSeriesStatuses
      .map { $0.displayName }
      .sorted()

    let logicSymbol = browseOpts.seriesStatusLogic == .all ? "∧" : "∨"

    var parts: [String] = []
    if !includeNames.isEmpty {
      parts.append(includeNames.joined(separator: " \(logicSymbol) "))
    }
    if !excludeNames.isEmpty {
      parts.append("≠ " + excludeNames.joined(separator: " \(logicSymbol) "))
    }

    guard !parts.isEmpty else { return nil }
    let variant: FilterChipVariant = includeNames.isEmpty ? .negative : .normal
    return (label: parts.joined(separator: ", "), variant: variant)
  }
}
