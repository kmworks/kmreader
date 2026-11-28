//
// SearchViewModel.swift
//
//

import Foundation

/// All-category search overview (Series, Books, Collections, Read Lists) for a
/// submitted query and library scope. Each category reuses its browse view
/// model with a small preview window so server sync, GRDB upserts, pinning,
/// and offline queries behave identically to the category detail pages.
@MainActor
@Observable
final class SearchViewModel {
  static let previewPageSize = 12

  let seriesViewModel = SeriesViewModel(pageSize: previewPageSize)
  let bookViewModel = BookViewModel(pageSize: previewPageSize)
  let collectionsViewModel = CollectionsViewModel(pageSize: previewPageSize)
  let readListsViewModel = ReadListsViewModel(pageSize: previewPageSize)

  private(set) var isLoading = false
  private var searchID = UUID()
  private var loadedKey: String?

  var failureMessage: String? {
    let errors = [
      seriesViewModel.loadError,
      bookViewModel.loadError,
      collectionsViewModel.loadError,
      readListsViewModel.loadError,
    ]
    for case let error? in errors {
      let message = ErrorManager.shared.handleError(error)
      if !message.isEmpty { return message }
    }
    return nil
  }

  var isEmpty: Bool {
    seriesViewModel.pagination.isEmpty
      && bookViewModel.pagination.isEmpty
      && collectionsViewModel.pagination.isEmpty
      && readListsViewModel.pagination.isEmpty
  }

  static func normalizedQuery(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// True when the settled results already match this query, scope, instance,
  /// and filter/sort configuration — returning from a pushed category page
  /// must not reset the strips.
  func hasLoaded(query: String, libraryIds: [String]) -> Bool {
    guard !isLoading else { return false }
    let trimmed = Self.normalizedQuery(query)
    guard !trimmed.isEmpty else { return false }
    return loadedKey == Self.loadKey(query: trimmed, libraryIds: libraryIds)
  }

  func search(query: String, libraryIds: [String]) async {
    let trimmed = Self.normalizedQuery(query)
    guard !trimmed.isEmpty else {
      clear()
      return
    }

    let id = UUID()
    searchID = id
    isLoading = true
    let key = Self.loadKey(query: trimmed, libraryIds: libraryIds)

    let ignoreFilters = AppConfig.searchIgnoreFilters
    let storedSeries =
      SeriesBrowseOptions(rawValue: AppConfig.seriesBrowseOptions) ?? SeriesBrowseOptions()
    let storedBooks =
      BookBrowseOptions(rawValue: AppConfig.bookBrowseOptions) ?? BookBrowseOptions()
    let seriesOpts = ignoreFilters ? storedSeries.filtersCleared : storedSeries
    let bookOpts = ignoreFilters ? storedBooks.filtersCleared : storedBooks
    let collectionSort =
      (SimpleSortOptions(rawValue: AppConfig.collectionSortOptions) ?? SimpleSortOptions())
      .sortString
    let readListSort =
      (SimpleSortOptions(rawValue: AppConfig.readListSortOptions) ?? SimpleSortOptions())
      .sortString

    async let series: Void = seriesViewModel.loadSeries(
      browseOpts: seriesOpts,
      searchText: trimmed,
      libraryIds: libraryIds,
      refresh: true,
      reportsErrors: false
    )
    async let books: Void = bookViewModel.loadBrowseBooks(
      browseOpts: bookOpts,
      searchText: trimmed,
      libraryIds: libraryIds,
      refresh: true,
      reportsErrors: false
    )
    async let collections: Void = collectionsViewModel.loadCollections(
      libraryIds: libraryIds,
      searchText: trimmed,
      sort: collectionSort,
      refresh: true,
      reportsErrors: false
    )
    // Previews render list cards only; hydrating automatic-policy member
    // books would stall every category behind unrelated book-page syncs.
    async let readLists: Void = readListsViewModel.loadReadLists(
      libraryIds: libraryIds,
      searchText: trimmed,
      sort: readListSort,
      refresh: true,
      reportsErrors: false,
      syncAutomaticBooks: false
    )
    _ = await (series, books, collections, readLists)

    guard searchID == id else { return }
    isLoading = false
    // Leaving the surface cancels the task without starting a replacement;
    // only completed searches may satisfy `hasLoaded` on return.
    if !Task.isCancelled {
      loadedKey = key
    }
  }

  func clear() {
    searchID = UUID()
    loadedKey = nil
    isLoading = false
  }

  private static func loadKey(query: String, libraryIds: [String]) -> String {
    [
      AppConfig.current.instanceId,
      AppConfig.isOffline ? "offline" : "online",
      AppConfig.searchIgnoreFilters ? "ignoreFilters" : "filters",
      AppConfig.seriesBrowseOptions,
      AppConfig.bookBrowseOptions,
      AppConfig.collectionSortOptions,
      AppConfig.readListSortOptions,
      libraryIds.joined(separator: ","),
      query,
    ].joined(separator: "|")
  }
}
