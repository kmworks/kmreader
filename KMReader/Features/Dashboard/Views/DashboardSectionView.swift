//
// DashboardSectionView.swift
//
//

import SwiftUI

/// One dashboard row. Pure renderer: `DashboardViewModel` owns loading and
/// reloads, so the row carries no lifecycle or notification modifiers.
@MainActor
struct DashboardSectionView: View {
  let section: DashboardSection
  let viewModel: DashboardViewModel

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  private var cardKind: DashboardCardKind {
    dashboard.cardKind(for: section)
  }

  private var itemWidth: CGFloat {
    cardKind.cardWidth
  }

  private var horizontalCoverWidth: CGFloat? {
    cardKind == .horizontal ? LayoutConfig.horizontalCoverWidth : nil
  }

  var body: some View {
    DashboardSectionLayout(
      section: section,
      destination: .dashboardSectionDetail(section: section),
      showsCardKindMenu: true,
      isEmpty: viewModel.isEmpty(for: section),
      itemIds: viewModel.items(for: section).map(\.id)
    ) {
      LazyHStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
        ForEach(viewModel.items(for: section)) { item in
          itemView(for: item.id)
            .id(item.id)
            .frame(width: itemWidth)
        }
      }
    }
  }

  @ViewBuilder
  private func itemView(for itemId: String) -> some View {
    switch section.contentKind {
    case .books:
      BookQueryItemView(
        bookId: itemId,
        layout: .grid,
        showSeriesTitle: true,
        horizontalCoverWidth: horizontalCoverWidth,
        coverOnly: cardKind == .small,
        cardWidth: itemWidth,
        onItemMissing: {
          viewModel.removeItem(section: section, id: itemId)
        }
      )
    case .series:
      SeriesQueryItemView(
        seriesId: itemId,
        layout: .grid,
        coverOnly: cardKind == .small,
        cardWidth: itemWidth,
        onItemMissing: {
          viewModel.removeItem(section: section, id: itemId)
        }
      )
    }
  }
}
