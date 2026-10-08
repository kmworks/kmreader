//
// SeriesDetailWideLayoutView.swift
//
//

import SwiftUI

/// Wide series detail (iPad regular width, macOS wide windows): the rail
/// carries identity and about-info (cover, hero info, action card, summary,
/// metadata detail, timestamps); collections and the books list flow in the
/// right column.
struct SeriesDetailWideLayoutView<Actions: View>: View {
  let series: Series
  let item: SeriesDisplayItem?
  let collections: [SidebarCollectionItem]
  let seriesId: String
  let availableWidth: CGFloat
  @Bindable var bookViewModel: BookViewModel
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool
  @ViewBuilder let actions: Actions

  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  /// Cover stays narrower than the rail instead of filling it edge to edge.
  private let coverWidth: CGFloat = LayoutConfig.detailWideCoverWidth

  /// Action card caps its width inside the rail, like the cover.
  private let cardWidthCap: CGFloat = 400

  init(
    series: Series,
    item: SeriesDisplayItem?,
    collections: [SidebarCollectionItem],
    seriesId: String,
    availableWidth: CGFloat,
    bookViewModel: BookViewModel,
    showFilterSheet: Binding<Bool>,
    showSavedFilters: Binding<Bool>,
    @ViewBuilder actions: () -> Actions
  ) {
    self.series = series
    self.item = item
    self.collections = collections
    self.seriesId = seriesId
    self.availableWidth = availableWidth
    self.bookViewModel = bookViewModel
    self._showFilterSheet = showFilterSheet
    self._showSavedFilters = showSavedFilters
    self.actions = actions()
  }

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && series.isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  var body: some View {
    DetailWideLayoutView(availableWidth: availableWidth) { railWidth in
      VStack(alignment: .leading, spacing: 20) {
        DetailCoverView(
          id: series.id,
          type: .series,
          contentBlurRadius: coverBlurRadius,
          width: coverWidth,
          cornerRadius: 12
        )
        .frame(maxWidth: .infinity, alignment: .center)

        SeriesHeroInfoView(series: series)
          .environment(\.detailHeroCentered, true)

        DetailActionCard {
          SeriesBookCountView(series: series)
          actions
        }
        .environment(\.detailHeroCentered, true)
        .frame(width: min(cardWidthCap, railWidth))
        .frame(maxWidth: .infinity, alignment: .center)

        DetailTimestampsView(created: series.created, lastModified: series.lastModified)
          .frame(maxWidth: .infinity, alignment: .center)

        VStack(alignment: .leading, spacing: 16) {
          SeriesSummaryView(series: series)
          SeriesDetailChipsView(series: series)
          SeriesAlternateTitlesView(series: series)
        }
      }
    } column: {
      if item != nil {
        VStack(alignment: .leading, spacing: 20) {
          DetailMembershipSection(collections: collections)
            .padding(.horizontal)

          BooksListViewForSeries(
            seriesId: seriesId,
            bookViewModel: bookViewModel,
            showFilterSheet: $showFilterSheet,
            showSavedFilters: $showSavedFilters
          )
        }
      }
    }
  }
}
