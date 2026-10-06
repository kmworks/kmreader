//
// BrowseContentView.swift
//
//

import SwiftUI

/// The scrollable content of a browse page: optional library header, the
/// content-type menu (when browsing across types), the search placeholder,
/// and the per-type content. The chrome around it (search field, toolbar,
/// navigation title, refresh triggers) belongs to the enclosing shell —
/// `BrowseView` for standalone pages, `DashboardSearchResultsView` for the
/// Dashboard search overlay.
struct BrowseContentView: View {
  let fixedContent: BrowseContentType?
  let metadataFilter: MetadataFilterConfig?
  /// Search mode: show a search placeholder until a query is entered instead
  /// of browsing all content.
  let searchOnly: Bool
  /// The submitted query driving results; empty shows the placeholder in
  /// search mode, or all content otherwise.
  let searchText: String
  let refreshTrigger: UUID
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool
  /// Explicit library scope (empty = all libraries). When nil, falls back to
  /// the pushed single-library selection, then the pinned set.
  let libraryIds: [String]?
  /// In-place scope of the iPhone Library tab root; its header and the
  /// single-library section counts come from `scopeLibraries`.
  let libraryScope: LibraryBrowseScope?
  let scopeLibraries: [SidebarLibraryItem]
  let allLibrariesEntry: SidebarLibraryItem?

  @Environment(\.browseLibrarySelection) private var librarySelection

  @AppStorage("browseContent") private var browseContent: BrowseContentType = .series
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  init(
    fixedContent: BrowseContentType? = nil,
    metadataFilter: MetadataFilterConfig? = nil,
    searchOnly: Bool = false,
    searchText: String = "",
    refreshTrigger: UUID,
    showFilterSheet: Binding<Bool> = .constant(false),
    showSavedFilters: Binding<Bool> = .constant(false),
    libraryIds: [String]? = nil,
    libraryScope: LibraryBrowseScope? = nil,
    scopeLibraries: [SidebarLibraryItem] = [],
    allLibrariesEntry: SidebarLibraryItem? = nil
  ) {
    self.fixedContent = fixedContent
    self.metadataFilter = metadataFilter
    self.searchOnly = searchOnly
    self.searchText = searchText
    self.refreshTrigger = refreshTrigger
    self._showFilterSheet = showFilterSheet
    self._showSavedFilters = showSavedFilters
    self.libraryIds = libraryIds
    self.libraryScope = libraryScope
    self.scopeLibraries = scopeLibraries
    self.allLibrariesEntry = allLibrariesEntry
  }

  /// Library browse (split view) offers only series/books; collections and
  /// read lists live at the sidebar's top level.
  private var availableContentTypes: [BrowseContentType] {
    guard librarySelection == nil else { return [.series, .books] }
    return BrowseContentType.allCases
  }

  private var effectiveContent: BrowseContentType {
    .effective(fixed: fixedContent, libraryScoped: librarySelection != nil, persisted: browseContent)
  }

  /// The menu reads the effective content so a persisted collections/read
  /// lists selection still shows Series selected inside library browse,
  /// where only series/books are offered.
  private var browseContentBinding: Binding<BrowseContentType> {
    Binding(
      get: { effectiveContent },
      set: { browseContent = $0 }
    )
  }

  private var resolvedLibraryIds: [String] {
    if let libraryIds {
      return libraryIds
    }
    if let library = librarySelection {
      return [library.libraryId]
    }
    return dashboard.libraryIds
  }

  /// The library whose section counts are shown: the in-place tab scope
  /// first, then the pushed browse selection.
  private var headerLibraryItem: SidebarLibraryItem? {
    if let id = libraryScope?.libraryId {
      return scopeLibraries.first(where: { $0.libraryId == id })
    }
    return librarySelection.map(SidebarLibraryItem.init(selection:))
  }

  private func sectionCount(browseContent: BrowseContentType) -> Int? {
    guard let library = headerLibraryItem else { return nil }
    switch browseContent {
    case .series:
      return library.seriesCount.map { Int($0) }
    case .books:
      return library.booksCount.map { Int($0) }
    case .collections, .readlists:
      return nil
    }
  }

  private var sectionCounts: [BrowseContentType: Int] {
    availableContentTypes.reduce(into: [:]) { result, type in
      result[type] = sectionCount(browseContent: type)
    }
  }

  /// Caption trailing the content-type chip: the scope title in medium
  /// weight, then the covered libraries' metrics in secondary. Nil on
  /// unscoped pages (no tab scope and no pushed library selection).
  private var chipCaption: Text? {
    let title: String?
    let facts: SidebarLibraryItem?
    if let libraryScope {
      title = libraryScope.title(pinnedIds: dashboard.libraryIds, libraries: scopeLibraries)
      facts = libraryScope.facts(
        pinnedIds: dashboard.libraryIds, libraries: scopeLibraries,
        allLibrariesEntry: allLibrariesEntry)
    } else if let selection = librarySelection {
      title = selection.name
      facts = SidebarLibraryItem(selection: selection)
    } else {
      return nil
    }
    guard let title else { return nil }
    return LibraryMetricsText.scopeCaption(
      title: title,
      facts: facts.flatMap { LibraryMetricsText.sizeAndMetrics(for: $0) })
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if fixedContent == nil && !(searchOnly && searchText.isEmpty) {
          HStack {
            BrowseContentTypeMenu(
              selection: browseContentBinding,
              types: availableContentTypes,
              counts: sectionCounts
            )
            if let chipCaption {
              chipCaption
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer()
          }
          .padding(.horizontal)
          .padding(.vertical, 8)
        }

        if searchOnly && searchText.isEmpty {
          ContentUnavailableView {
            Label(String(localized: "tab.search", defaultValue: "Search"), systemImage: "magnifyingglass")
          } description: {
            Text(
              String(
                localized: "search.empty.hint",
                defaultValue: "Search series, books, collections, and read lists."))
          }
          .frame(maxWidth: .infinity, minHeight: 320)
        } else {
          browseContentView
        }
      }
    }
  }

  @ViewBuilder
  private var browseContentView: some View {
    switch effectiveContent {
    case .series:
      SeriesBrowseView(
        libraryIds: resolvedLibraryIds,
        searchText: searchText,
        refreshTrigger: refreshTrigger,
        metadataFilter: metadataFilter,
        showFilterSheet: $showFilterSheet,
        showSavedFilters: $showSavedFilters,
      )
    case .books:
      BooksBrowseView(
        libraryIds: resolvedLibraryIds,
        searchText: searchText,
        refreshTrigger: refreshTrigger,
        metadataFilter: metadataFilter,
        showFilterSheet: $showFilterSheet,
        showSavedFilters: $showSavedFilters,
      )
    case .collections:
      CollectionsBrowseView(
        libraryIds: resolvedLibraryIds,
        searchText: searchText,
        refreshTrigger: refreshTrigger,
        showFilterSheet: $showFilterSheet
      )
    case .readlists:
      ReadListsBrowseView(
        libraryIds: resolvedLibraryIds,
        searchText: searchText,
        refreshTrigger: refreshTrigger,
        showFilterSheet: $showFilterSheet
      )
    }
  }
}
