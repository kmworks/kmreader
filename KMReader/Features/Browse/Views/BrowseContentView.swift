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

  /// The metrics item behind the chip caption and the content-type counts:
  /// the in-place tab scope's covered libraries first, then the pushed
  /// browse selection.
  private var headerFacts: SidebarLibraryItem? {
    if let libraryScope {
      return libraryScope.facts(
        pinnedIds: dashboard.libraryIds, libraries: scopeLibraries,
        allLibrariesEntry: allLibrariesEntry)
    }
    return librarySelection.map(SidebarLibraryItem.init(selection:))
  }

  private func sectionCount(browseContent: BrowseContentType) -> Int? {
    guard let facts = headerFacts else { return nil }
    switch browseContent {
    case .series:
      return facts.seriesCount.map { Int($0) }
    case .books:
      return facts.booksCount.map { Int($0) }
    case .collections:
      return facts.collectionsCount.map { Int($0) }
    case .readlists:
      return facts.readlistsCount.map { Int($0) }
    }
  }

  private var sectionCounts: [BrowseContentType: Int] {
    availableContentTypes.reduce(into: [:]) { result, type in
      result[type] = sectionCount(browseContent: type)
    }
  }

  /// Caption trailing the content-type chip: the scope title in medium
  /// weight, then the covered libraries' file size in secondary (the counts
  /// live on the chip itself). Nil on unscoped pages (no tab scope and no
  /// pushed library selection).
  private var chipCaption: Text? {
    let title: String?
    if let libraryScope {
      title = libraryScope.title(pinnedIds: dashboard.libraryIds, libraries: scopeLibraries)
    } else if let selection = librarySelection {
      title = selection.name
    } else {
      return nil
    }
    guard let title else { return nil }
    return LibraryMetricsText.scopeCaption(
      title: title,
      facts: headerFacts?.fileSize.map { Text($0.humanReadableFileSize) })
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
            Label(String(localized: "tab.search", defaultValue: "Search"), systemImage: AppIcon.search)
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
