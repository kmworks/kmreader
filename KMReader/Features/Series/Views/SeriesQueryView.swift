//
// SeriesQueryView.swift
//
//

import SwiftUI

struct SeriesQueryView: View {
  let libraryIds: [String]
  let searchText: String
  let browseOpts: SeriesBrowseOptions
  let browseLayout: BrowseLayoutMode
  let viewModel: SeriesViewModel
  let useLocalOnly: Bool
  let offlineOnly: Bool
  /// Non-nil enters selection mode with this selection binding.
  let selectedSeriesIds: Binding<Set<String>>?

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  init(
    libraryIds: [String],
    searchText: String,
    browseOpts: SeriesBrowseOptions,
    browseLayout: BrowseLayoutMode,
    viewModel: SeriesViewModel,
    useLocalOnly: Bool = false,
    offlineOnly: Bool = false,
    selectedSeriesIds: Binding<Set<String>>? = nil
  ) {
    self.libraryIds = libraryIds
    self.searchText = searchText
    self.browseOpts = browseOpts
    self.browseLayout = browseLayout
    self.viewModel = viewModel
    self.useLocalOnly = useLocalOnly
    self.offlineOnly = offlineOnly
    self.selectedSeriesIds = selectedSeriesIds
  }

  var body: some View {
    BrowseStateView(
      isLoading: viewModel.isLoading,
      isEmpty: viewModel.pagination.isEmpty,
      emptyIcon: ContentIcon.series,
      emptyTitle: LocalizedStringKey("No series found"),
      emptyMessage: LocalizedStringKey("Try selecting a different library."),
      onRetry: {
        loadSeries(refresh: true)
      }
    ) {
      switch browseLayout {
      case .grid, .largeGrid:
        LazyVGrid(columns: columns, spacing: spacing) {
          ForEach(viewModel.pagination.items) { series in
            Group {
              if let selectedSeriesIds {
                SeriesSelectionItemView(
                  seriesId: series.id,
                  layout: browseLayout,
                  selectedSeriesIds: selectedSeriesIds,
                  cardWidth: browseLayout.cardWidth
                )
              } else {
                SeriesQueryItemView(
                  seriesId: series.id,
                  layout: browseLayout,
                  cardWidth: browseLayout.cardWidth,
                  onItemMissing: {
                    viewModel.removeSeries(id: series.id)
                  }
                )
              }
            }
            .onAppear {
              if viewModel.pagination.shouldLoadMore(after: series) {
                loadSeries(refresh: false)
              }
            }
          }
        }
        .padding(.horizontal)
      case .list:
        LazyVStack {
          ForEach(viewModel.pagination.items) { series in
            Group {
              if let selectedSeriesIds {
                SeriesSelectionItemView(
                  seriesId: series.id,
                  layout: .list,
                  selectedSeriesIds: selectedSeriesIds
                )
              } else {
                SeriesQueryItemView(
                  seriesId: series.id,
                  layout: .list,
                  onItemMissing: {
                    viewModel.removeSeries(id: series.id)
                  }
                )
              }
            }
            .onAppear {
              if viewModel.pagination.shouldLoadMore(after: series) {
                loadSeries(refresh: false)
              }
            }
            if !viewModel.pagination.isLast(series) {
              Divider()
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  private func loadSeries(refresh: Bool) {
    Task {
      await viewModel.loadSeries(
        browseOpts: browseOpts,
        searchText: searchText,
        libraryIds: libraryIds,
        refresh: refresh,
        useLocalOnly: useLocalOnly,
        offlineOnly: offlineOnly
      )
    }
  }
}
