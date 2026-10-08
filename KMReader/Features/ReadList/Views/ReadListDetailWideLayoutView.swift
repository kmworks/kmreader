//
// ReadListDetailWideLayoutView.swift
//
//

import SwiftUI

/// Wide read list detail (iPad regular width, macOS wide windows): the rail
/// carries identity and the action card (cover, hero info, book count,
/// offline actions); the books list flows in the right column.
struct ReadListDetailWideLayoutView<Actions: View>: View {
  let readList: ReadList
  let item: ReadListDisplayItem?
  let readListId: String
  let availableWidth: CGFloat
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool
  @ViewBuilder let actions: Actions

  /// Cover stays narrower than the rail instead of filling it edge to edge.
  private let coverWidth: CGFloat = LayoutConfig.detailWideCoverWidth

  /// Action card caps its width inside the rail, like the cover.
  private let cardWidthCap: CGFloat = 400

  var body: some View {
    DetailWideLayoutView(availableWidth: availableWidth) { railWidth in
      VStack(alignment: .leading, spacing: 20) {
        DetailCoverView(
          id: readList.id,
          type: .readlist,
          width: coverWidth,
          cornerRadius: 12
        )
        .frame(maxWidth: .infinity, alignment: .center)

        ReadListHeroInfoView(readList: readList)
          .environment(\.detailHeroCentered, true)

        DetailActionCard {
          ReadListBookCountView(readList: readList)

          actions
        }
        .environment(\.detailHeroCentered, true)
        .frame(width: min(cardWidthCap, railWidth))
        .frame(maxWidth: .infinity, alignment: .center)

        DetailTimestampsView(
          created: readList.createdDate, lastModified: readList.lastModifiedDate
        )
        .frame(maxWidth: .infinity, alignment: .center)
      }
    } column: {
      if item != nil {
        VStack(alignment: .leading, spacing: 20) {
          BooksListViewForReadList(
            readListId: readListId,
            showFilterSheet: $showFilterSheet,
            showSavedFilters: $showSavedFilters
          )
        }
      }
    }
  }
}
