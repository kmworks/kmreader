//
// SeriesDetailContentView.swift
//
//

import SwiftUI

struct SeriesDetailContentView<Actions: View>: View {
  let series: Series
  @ViewBuilder let actions: Actions

  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  /// Measured width driving the centered/leading header switch. Defaults wide
  /// where the leading layout can engage (iPad, macOS) so the first frame
  /// doesn't flash centered.
  #if os(macOS)
    @State private var contentWidth: CGFloat = .infinity
  #else
    @State private var contentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  init(series: Series, @ViewBuilder actions: () -> Actions) {
    self.series = series
    self.actions = actions()
  }

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && series.isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  private var isNarrowLayout: Bool {
    contentWidth < LayoutConfig.detailWideLayoutMinimumWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Group {
        DetailHeroView(
          id: series.id,
          type: .series,
          contentBlurRadius: coverBlurRadius
        ) {
          SeriesHeroInfoView(series: series)
        }

        DetailActionCard {
          SeriesBookCountView(series: series)

          actions
        }
        .frame(maxWidth: isNarrowLayout ? 480 : .infinity)
        .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)

        DetailTimestampsView(created: series.created, lastModified: series.lastModified)
          .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)
      }
      .environment(\.detailHeroCentered, isNarrowLayout)

      SeriesSummaryView(series: series)

      SeriesDetailChipsView(series: series)

      SeriesAlternateTitlesView(series: series)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
  }
}
