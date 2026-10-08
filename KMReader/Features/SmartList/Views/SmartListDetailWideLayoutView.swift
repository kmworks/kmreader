//
// SmartListDetailWideLayoutView.swift
//
//

import SwiftUI

/// Wide smart list detail (iPad regular width, macOS wide windows): the rail
/// carries identity (cover, hero info, timestamps); the member list flows in
/// the right column.
struct SmartListDetailWideLayoutView: View {
  let smartList: SmartList
  let availableWidth: CGFloat

  /// Cover stays narrower than the rail instead of filling it edge to edge.
  private let coverWidth: CGFloat = LayoutConfig.detailWideCoverWidth

  var body: some View {
    DetailWideLayoutView(availableWidth: availableWidth) { _ in
      VStack(alignment: .leading, spacing: 20) {
        DetailCoverView(
          id: smartList.id,
          type: .smartList,
          width: coverWidth,
          cornerRadius: 12
        )
        .frame(maxWidth: .infinity, alignment: .center)

        SmartListHeroInfoView(smartList: smartList)
          .environment(\.detailHeroCentered, true)

        DetailTimestampsView(
          created: smartList.createdDate, lastModified: smartList.lastModifiedDate
        )
        .frame(maxWidth: .infinity, alignment: .center)
      }
    } column: {
      VStack(alignment: .leading, spacing: 20) {
        switch smartList.target {
        case .book:
          SmartListBooksListView(smartListId: smartList.id)
        case .series:
          SmartListSeriesListView(smartListId: smartList.id)
        }
      }
    }
  }
}
