//
// SearchResultsContentView.swift
//
//

import SwiftUI

/// Scrollable all-category search results. Reads `SearchViewModel` directly
/// so the enclosing shell can own `.refreshable` without re-rendering (and
/// cancelling) the in-flight refresh action when the view model updates.
struct SearchResultsContentView: View {
  let query: String
  let scope: LibraryBrowseScope
  let viewModel: SearchViewModel

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  private var libraryIds: [String] {
    scope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private func destination(for category: BrowseContentType) -> NavDestination {
    .searchCategory(category: category, query: query, scope: scope)
  }

  var body: some View {
    ScrollView {
      if !viewModel.hasLoaded(query: query, libraryIds: libraryIds) {
        SearchResultsSkeletonView()
      } else if let failureMessage = viewModel.failureMessage {
        ContentUnavailableView {
          Label(String(localized: "Search failed"), systemImage: AppIcon.loadError)
        } description: {
          Text(failureMessage)
        } actions: {
          Button(String(localized: "Retry")) {
            Task {
              await viewModel.search(query: query, libraryIds: libraryIds)
            }
          }
          .adaptiveButtonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
      } else if viewModel.isEmpty {
        ContentUnavailableView.search(text: query)
          .frame(maxWidth: .infinity, minHeight: 320)
      } else {
        VStack(spacing: 0) {
          seriesSection
          booksSection
          collectionsSection
          readListsSection
        }
      }
    }
  }

  @ViewBuilder
  private var seriesSection: some View {
    let vm = viewModel.seriesViewModel
    let items = previewItems(vm.pagination.items)
    if !items.isEmpty {
      SearchCategorySectionView(
        category: .series,
        totalCount: vm.totalCount,
        showsViewAll: showsViewAll(
          totalCount: vm.totalCount,
          loadedCount: vm.pagination.items.count,
          previewCount: items.count,
          hasMore: vm.pagination.hasMorePages
        ),
        destination: destination(for: .series),
        itemIds: items.map(\.id)
      ) {
        ForEach(items) { item in
          SeriesQueryItemView(
            seriesId: item.id,
            layout: .grid,
            cardWidth: LayoutConfig.gridCardWidth,
            onItemMissing: {
              vm.removeSeries(id: item.id)
            }
          )
          .id(item.id)
          .frame(width: LayoutConfig.gridCardWidth)
        }
      }
    }
  }

  @ViewBuilder
  private var booksSection: some View {
    let vm = viewModel.bookViewModel
    let items = previewItems(vm.pagination.items)
    if !items.isEmpty {
      SearchCategorySectionView(
        category: .books,
        totalCount: vm.totalCount,
        showsViewAll: showsViewAll(
          totalCount: vm.totalCount,
          loadedCount: vm.pagination.items.count,
          previewCount: items.count,
          hasMore: vm.pagination.hasMorePages
        ),
        destination: destination(for: .books),
        itemIds: items.map(\.id)
      ) {
        ForEach(items) { item in
          BookQueryItemView(
            bookId: item.id,
            layout: .grid,
            showSeriesTitle: true,
            cardWidth: LayoutConfig.gridCardWidth,
            onItemMissing: {
              vm.removeBook(id: item.id)
            }
          )
          .id(item.id)
          .frame(width: LayoutConfig.gridCardWidth)
        }
      }
    }
  }

  @ViewBuilder
  private var collectionsSection: some View {
    let vm = viewModel.collectionsViewModel
    let items = previewItems(vm.pagination.items)
    if !items.isEmpty {
      SearchCategorySectionView(
        category: .collections,
        totalCount: vm.totalCount,
        showsViewAll: showsViewAll(
          totalCount: vm.totalCount,
          loadedCount: vm.pagination.items.count,
          previewCount: items.count,
          hasMore: vm.pagination.hasMorePages
        ),
        destination: destination(for: .collections),
        itemIds: items.map(\.id)
      ) {
        ForEach(items) { item in
          CollectionQueryItemView(
            collectionId: item.id,
            onItemMissing: {
              vm.removeCollection(id: item.id)
            }
          )
          .id(item.id)
          .frame(width: LayoutConfig.gridCardWidth)
        }
      }
    }
  }

  @ViewBuilder
  private var readListsSection: some View {
    let vm = viewModel.readListsViewModel
    let items = previewItems(vm.pagination.items)
    if !items.isEmpty {
      SearchCategorySectionView(
        category: .readlists,
        totalCount: vm.totalCount,
        showsViewAll: showsViewAll(
          totalCount: vm.totalCount,
          loadedCount: vm.pagination.items.count,
          previewCount: items.count,
          hasMore: vm.pagination.hasMorePages
        ),
        destination: destination(for: .readlists),
        itemIds: items.map(\.id)
      ) {
        ForEach(items) { item in
          ReadListQueryItemView(
            readListId: item.id,
            onItemMissing: {
              vm.removeReadList(id: item.id)
            }
          )
          .id(item.id)
          .frame(width: LayoutConfig.gridCardWidth)
        }
      }
    }
  }

  /// Pinned collections/read lists can prepend more items than `pageSize`;
  /// cap the eager strip so a preview never renders an unbounded row.
  private func previewItems(_ items: [IdentifiedString]) -> [IdentifiedString] {
    Array(items.prefix(SearchViewModel.previewPageSize))
  }

  private func showsViewAll(
    totalCount: Int?,
    loadedCount: Int,
    previewCount: Int,
    hasMore: Bool
  ) -> Bool {
    hasMore || loadedCount > previewCount || (totalCount ?? loadedCount) > previewCount
  }
}
