//
// ReadListDetailContentView.swift
//
//

import SwiftUI

struct ReadListDetailContentView<Actions: View>: View {
  let readList: ReadList
  @ViewBuilder let actions: Actions

  /// Measured width driving the centered/leading header switch. Defaults wide
  /// where the leading layout can engage (iPad, macOS) so the first frame
  /// doesn't flash centered.
  #if os(macOS)
    @State private var contentWidth: CGFloat = .infinity
  #else
    @State private var contentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  init(
    readList: ReadList,
    @ViewBuilder actions: () -> Actions
  ) {
    self.readList = readList
    self.actions = actions()
  }

  private var isNarrowLayout: Bool {
    contentWidth < LayoutConfig.detailWideLayoutMinimumWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DetailHeroView(
        id: readList.id,
        type: .readlist,
        contentBlurRadius: 0
      ) {
        ReadListHeroInfoView(readList: readList)
      }

      DetailActionCard {
        ReadListBookCountView(readList: readList)

        actions
      }
      .frame(maxWidth: isNarrowLayout ? 480 : .infinity)
      .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)

      DetailTimestampsView(
        created: readList.createdDate, lastModified: readList.lastModifiedDate
      )
      .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
    .environment(\.detailHeroCentered, isNarrowLayout)
  }
}
