//
// CollectionDetailWideLayoutView.swift
//
//

import SwiftUI

/// Wide collection detail (iPad regular width, macOS wide windows): the
/// rail carries identity and the action card (cover, hero info, series
/// count); the series list flows in the right column.
struct CollectionDetailWideLayoutView: View {
  let collection: SeriesCollection
  let item: CollectionDisplayItem?
  let collectionId: String
  let availableWidth: CGFloat
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  /// Cover stays narrower than the rail instead of filling it edge to edge.
  private let coverWidth: CGFloat = LayoutConfig.detailWideCoverWidth

  /// Action card caps its width inside the rail, like the cover.
  private let cardWidthCap: CGFloat = 400

  var body: some View {
    DetailWideLayoutView(availableWidth: availableWidth) { railWidth in
      VStack(alignment: .leading, spacing: 20) {
        DetailCoverView(
          id: collection.id,
          type: .collection,
          width: coverWidth,
          cornerRadius: 12
        )
        .frame(maxWidth: .infinity, alignment: .center)

        CollectionHeroInfoView(collection: collection)
          .environment(\.detailHeroCentered, true)

        DetailActionCard {
          CollectionBookCountView(collection: collection)
        }
        .environment(\.detailHeroCentered, true)
        .frame(width: min(cardWidthCap, railWidth))
        .frame(maxWidth: .infinity, alignment: .center)

        DetailTimestampsView(
          created: collection.createdDate, lastModified: collection.lastModifiedDate
        )
        .frame(maxWidth: .infinity, alignment: .center)
      }
    } column: {
      if item != nil {
        VStack(alignment: .leading, spacing: 20) {
          CollectionSeriesListView(
            collectionId: collectionId,
            showFilterSheet: $showFilterSheet,
            showSavedFilters: $showSavedFilters
          )
        }
      }
    }
  }
}
