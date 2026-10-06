//
// BookFilterView.swift
//
//

import SwiftUI

struct BookFilterView: View {
  @Binding var browseOpts: BookBrowseOptions
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool
  let filterType: SavedFilterType
  let seriesId: String?
  let libraryIds: [String]?
  let includeOfflineSorts: Bool
  let usesRelevanceSort: Bool
  let ignoresFiltersForSearch: Bool
  let layoutMode: Binding<BrowseLayoutMode>?

  init(
    browseOpts: Binding<BookBrowseOptions>,
    showFilterSheet: Binding<Bool>,
    showSavedFilters: Binding<Bool>,
    filterType: SavedFilterType = .books,
    seriesId: String? = nil,
    libraryIds: [String]? = nil,
    includeOfflineSorts: Bool = false,
    usesRelevanceSort: Bool = false,
    ignoresFiltersForSearch: Bool = false,
    layoutMode: Binding<BrowseLayoutMode>? = nil
  ) {
    self._browseOpts = browseOpts
    self._showFilterSheet = showFilterSheet
    self._showSavedFilters = showSavedFilters
    self.filterType = filterType
    self.seriesId = seriesId
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
    usesRelevanceSort ? AppIcon.search : AppIcon.sort
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
      BookBrowseOptionsSheet(
        browseOpts: $browseOpts,
        filterType: filterType,
        seriesId: seriesId,
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
        systemImage: AppIcon.filterCircle,
        openSheet: $showFilterSheet
      )
    } else {
      if let label = buildReadStatusLabel(
        include: browseOpts.includeReadStatuses,
        exclude: browseOpts.excludeReadStatuses
      ) {
        FilterChip(
          label: label,
          systemImage: "eye",
          variant: label.contains("≠") ? .negative : .normal,
          openSheet: $showFilterSheet
        )
      }

      if browseOpts.oneshotFilter.isActive,
        let label = browseOpts.oneshotFilter.displayLabel(using: { _ in FilterStrings.oneshot })
      {
        FilterChip(
          label: label,
          systemImage: ContentIcon.oneshot,
          variant: browseOpts.oneshotFilter.state == .exclude ? .negative : .normal,
          openSheet: $showFilterSheet
        )
      }

      if browseOpts.deletedFilter.isActive,
        let label = browseOpts.deletedFilter.displayLabel(using: { _ in FilterStrings.deleted })
      {
        FilterChip(
          label: label,
          systemImage: AppIcon.delete,
          variant: browseOpts.deletedFilter.state == .exclude ? .negative : .normal,
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

      if let tags = browseOpts.metadataFilter.tags, !tags.isEmpty {
        let logicSymbol = browseOpts.metadataFilter.tagsLogic == .all ? "∧" : "∨"
        let label = tags.joined(separator: " \(logicSymbol) ")
        FilterChip(
          label: label,
          systemImage: "tag",
          openSheet: $showFilterSheet
        )
      }
    }
  }
}
