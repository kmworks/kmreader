//
// CollectionDetailContentView.swift
//
//

import SwiftUI

struct CollectionDetailContentView: View {
  let collection: SeriesCollection

  /// Measured width driving the centered/leading header switch. Defaults wide
  /// where the leading layout can engage (iPad, macOS) so the first frame
  /// doesn't flash centered.
  #if os(macOS)
    @State private var contentWidth: CGFloat = .infinity
  #else
    @State private var contentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  init(collection: SeriesCollection) {
    self.collection = collection
  }

  private var isNarrowLayout: Bool {
    contentWidth < LayoutConfig.detailWideLayoutMinimumWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DetailHeroView(
        id: collection.id,
        type: .collection,
        contentBlurRadius: 0
      ) {
        CollectionHeroInfoView(collection: collection)
      }

      DetailActionCard {
        CollectionBookCountView(collection: collection)
      }
      .frame(maxWidth: isNarrowLayout ? 480 : .infinity)
      .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)

      DetailTimestampsView(
        created: collection.createdDate, lastModified: collection.lastModifiedDate
      )
      .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
    .environment(\.detailHeroCentered, isNarrowLayout)
  }
}
