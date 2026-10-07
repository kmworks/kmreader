//
// SmartListDetailContentView.swift
//
//

import SwiftUI

struct SmartListDetailContentView: View {
  let smartList: SmartList

  /// Measured width driving the centered/leading header switch. Defaults wide
  /// where the leading layout can engage (iPad, macOS) so the first frame
  /// doesn't flash centered.
  #if os(macOS)
    @State private var contentWidth: CGFloat = .infinity
  #else
    @State private var contentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  private var isNarrowLayout: Bool {
    contentWidth < LayoutConfig.detailWideLayoutMinimumWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DetailHeroView(
        id: smartList.id,
        type: .smartList,
        contentBlurRadius: 0
      ) {
        SmartListHeroInfoView(smartList: smartList)
      }

      DetailTimestampsView(
        created: smartList.createdDate, lastModified: smartList.lastModifiedDate
      )
      .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
    .environment(\.detailHeroCentered, isNarrowLayout)
  }
}
