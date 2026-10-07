//
// SmartListSeriesListView.swift
//
//

import SwiftUI

// Series member list of a series-targeted smart list
struct SmartListSeriesListView: View {
  let smartListId: String

  @AppStorage("smartListSeriesBrowseLayout") private var layoutMode: BrowseLayoutMode = .list
  @AppStorage("smartListSeriesBrowseOptions") private var browseOpts: SeriesBrowseOptions =
    SeriesBrowseOptions()

  @State private var seriesViewModel = SeriesViewModel()
  @State private var showFilterSheet = false
  @State private var loadedSmartListId: String?

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: layoutMode.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        SeriesFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: .constant(false),
          showsPresets: false,
          layoutMode: $layoutMode
        )
      }
      .padding(.horizontal)

      BrowseStateView(
        isLoading: seriesViewModel.isLoading,
        isEmpty: seriesViewModel.pagination.isEmpty,
        emptyIcon: ContentIcon.series,
        emptyTitle: LocalizedStringKey("No series found"),
        emptyMessage: LocalizedStringKey("Try adjusting the filters."),
        onRetry: {
          Task { await loadSeries(refresh: true) }
        }
      ) {
        switch layoutMode {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(seriesViewModel.pagination.items) { series in
              SeriesQueryItemView(
                seriesId: series.id,
                layout: layoutMode,
                cardWidth: layoutMode.cardWidth,
                onItemMissing: {
                  seriesViewModel.removeSeries(id: series.id)
                }
              )
              .onAppear {
                if seriesViewModel.pagination.shouldLoadMore(after: series) {
                  Task { await loadSeries(refresh: false) }
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(seriesViewModel.pagination.items) { series in
              SeriesQueryItemView(
                seriesId: series.id,
                layout: .list,
                onItemMissing: {
                  seriesViewModel.removeSeries(id: series.id)
                }
              )
              .onAppear {
                if seriesViewModel.pagination.shouldLoadMore(after: series) {
                  Task { await loadSeries(refresh: false) }
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
    .task(id: smartListId) {
      guard loadedSmartListId != smartListId else { return }
      loadedSmartListId = smartListId
      await loadSeries(refresh: true)
    }
    .onChange(of: browseOpts) {
      Task {
        await loadSeries(refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .seriesProjectionDidChange)) { _ in
      Task { await revalidateSeries() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListsDidChange)) { notification in
      guard notification.userInfo?["smartListId"] as? String == smartListId else { return }
      Task { await revalidateSeries() }
    }
  }

  private func loadSeries(refresh: Bool) async {
    await seriesViewModel.loadSmartListSeries(
      smartListId: smartListId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }

  /// The stored server-side filter may be read-status-based even when the
  /// overlay options are not, so every series change revalidates the window.
  private func revalidateSeries() async {
    await seriesViewModel.revalidateSmartListSeries(
      smartListId: smartListId,
      browseOpts: browseOpts
    )
  }
}
