//
// BrowseContentView.swift
//
//

import SwiftUI

/// The scrollable content of a browse page: optional library header, the
/// content-type picker (when browsing across types), the search placeholder,
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
  let showsLibraryHeader: Bool
  let refreshTrigger: UUID
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  @Environment(\.browseLibrarySelection) private var librarySelection

  @AppStorage("browseContent") private var browseContent: BrowseContentType = .series
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  init(
    fixedContent: BrowseContentType? = nil,
    metadataFilter: MetadataFilterConfig? = nil,
    searchOnly: Bool = false,
    searchText: String = "",
    showsLibraryHeader: Bool = true,
    refreshTrigger: UUID,
    showFilterSheet: Binding<Bool> = .constant(false),
    showSavedFilters: Binding<Bool> = .constant(false)
  ) {
    self.fixedContent = fixedContent
    self.metadataFilter = metadataFilter
    self.searchOnly = searchOnly
    self.searchText = searchText
    self.showsLibraryHeader = showsLibraryHeader
    self.refreshTrigger = refreshTrigger
    self._showFilterSheet = showFilterSheet
    self._showSavedFilters = showSavedFilters
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

  /// The picker reads the effective content so a persisted collections/read
  /// lists selection still shows Series highlighted inside library browse,
  /// where only series/books are offered.
  private var browseContentBinding: Binding<BrowseContentType> {
    Binding(
      get: { effectiveContent },
      set: { browseContent = $0 }
    )
  }

  private var resolvedLibraryIds: [String] {
    if let library = librarySelection {
      return [library.libraryId]
    }
    return dashboard.libraryIds
  }

  private func sectionCount(browseContent: BrowseContentType) -> Int? {
    guard let library = librarySelection else { return nil }
    switch browseContent {
    case .series:
      return library.seriesCount.map { Int($0) }
    case .books:
      return library.booksCount.map { Int($0) }
    case .collections, .readlists:
      return nil
    }
  }

  private func sectionTitle(browseContent: BrowseContentType) -> String {
    if let count = sectionCount(browseContent: browseContent) {
      return String(format: "%@ (%d)", browseContent.displayName, count)
    }
    return browseContent.displayName
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if showsLibraryHeader, let library = librarySelection {
          VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Image(systemName: ContentIcon.library)
              Text(library.name)
                .font(.title2)
              if let fileSize = library.fileSize {
                Text(fileSize.humanReadableFileSize)
                  .font(.subheadline)
                  .foregroundColor(.secondary)
              }
              Spacer()
            }
          }.padding()
        }

        if fixedContent == nil && !(searchOnly && searchText.isEmpty) {
          Picker("", selection: browseContentBinding) {
            ForEach(availableContentTypes) { type in
              Label(sectionTitle(browseContent: type), systemImage: type.icon)
                .labelStyle(.titleAndIcon)
                .tag(type)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(maxWidth: .infinity)
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
