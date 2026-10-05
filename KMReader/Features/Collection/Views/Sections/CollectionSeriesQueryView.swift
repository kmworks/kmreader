//
// CollectionSeriesQueryView.swift
//
//

import SwiftUI

struct CollectionSeriesQueryView: View {
  let collectionId: String
  @Bindable var seriesViewModel: SeriesViewModel
  let browseOpts: CollectionSeriesBrowseOptions
  let browseLayout: BrowseLayoutMode
  let isSelectionMode: Bool
  @Binding var selectedSeriesIds: Set<String>
  let isAdmin: Bool

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  var body: some View {
    BrowseStateView(
      isLoading: seriesViewModel.isLoading,
      isEmpty: seriesViewModel.pagination.isEmpty,
      emptyIcon: ContentIcon.series,
      emptyTitle: LocalizedStringKey("No series found"),
      emptyMessage: LocalizedStringKey("Try adjusting the filters."),
      onRetry: {
        Task { await loadMore(refresh: true) }
      }
    ) {
      switch browseLayout {
      case .grid, .largeGrid:
        LazyVGrid(columns: columns, spacing: spacing) {
          ForEach(seriesViewModel.pagination.items) { series in
            Group {
              if isSelectionMode && isAdmin {
                SeriesSelectionItemView(
                  seriesId: series.id,
                  layout: browseLayout,
                  selectedSeriesIds: $selectedSeriesIds,
                  cardWidth: browseLayout.cardWidth
                )
              } else {
                SeriesQueryItemView(
                  seriesId: series.id,
                  layout: browseLayout,
                  cardWidth: browseLayout.cardWidth,
                  onItemMissing: {
                    seriesViewModel.removeSeries(id: series.id)
                  }
                )
              }
            }
            .onAppear {
              if seriesViewModel.pagination.shouldLoadMore(after: series) {
                Task { await loadMore(refresh: false) }
              }
            }
          }
        }
        .padding(.horizontal)
      case .list:
        LazyVStack {
          ForEach(seriesViewModel.pagination.items) { series in
            Group {
              if isSelectionMode && isAdmin {
                SeriesSelectionItemView(
                  seriesId: series.id,
                  layout: .list,
                  selectedSeriesIds: $selectedSeriesIds
                )
              } else {
                SeriesQueryItemView(
                  seriesId: series.id,
                  layout: .list,
                  onItemMissing: {
                    seriesViewModel.removeSeries(id: series.id)
                  }
                )
              }
            }
            .onAppear {
              if seriesViewModel.pagination.shouldLoadMore(after: series) {
                Task { await loadMore(refresh: false) }
              }
            }
            if !seriesViewModel.pagination.isLast(series) {
              Divider()
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  private func loadMore(refresh: Bool) async {
    await seriesViewModel.loadCollectionSeries(
      collectionId: collectionId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }
}
