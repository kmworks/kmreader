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
    Group {
      if seriesViewModel.isLoading && seriesViewModel.pagination.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      } else {
        switch browseLayout {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(seriesViewModel.pagination.items) { series in
              Group {
                if isSelectionMode && isAdmin {
                  SeriesSelectionItemView(
                    seriesId: series.id,
                    layout: browseLayout,
                    selectedSeriesIds: $selectedSeriesIds
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
              .padding(.bottom)
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
  }

  private func loadMore(refresh: Bool) async {
    await seriesViewModel.loadCollectionSeries(
      collectionId: collectionId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }
}
