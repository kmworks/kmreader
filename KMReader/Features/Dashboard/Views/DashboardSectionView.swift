//
// DashboardSectionView.swift
//
//

import SwiftUI

@MainActor
struct DashboardSectionView: View {
  let section: DashboardSection

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  @State private var viewModel: DashboardSectionViewModel

  private let logger = AppLogger(.dashboard)

  init(section: DashboardSection) {
    self.section = section
    _viewModel = State(initialValue: DashboardSectionViewModel(section: section))
  }

  private var cardKind: DashboardCardKind {
    dashboard.cardKind(for: section)
  }

  private var itemWidth: CGFloat {
    cardKind.cardWidth
  }

  private var horizontalCoverWidth: CGFloat? {
    cardKind == .horizontal ? LayoutConfig.horizontalCoverWidth : nil
  }

  private var effectiveLibraryIds: [String] {
    DashboardLibraryScopeStore.shared.effectiveLibraryIds(pinned: dashboard.libraryIds)
  }

  var body: some View {
    DashboardSectionLayout(
      section: section,
      destination: .dashboardSectionDetail(section: section),
      showsCardKindMenu: true,
      isEmpty: viewModel.pagination.isEmpty,
      itemIds: viewModel.pagination.items.map(\.id)
    ) {
      LazyHStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
        ForEach(viewModel.pagination.items) { item in
          itemView(for: item.id)
            .id(item.id)
            .frame(width: itemWidth)
            .onAppear {
              viewModel.loadMoreIfNeeded(after: item, libraryIds: effectiveLibraryIds)
            }
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dashboardSectionsShouldReload)) {
      notification in
      guard let command = DashboardSectionRefreshNotifier.reloadCommand(from: notification) else {
        return
      }
      handleReloadCommand(command)
    }
    .onAppear {
      DashboardRefreshCoordinator.shared.registerSection(section)
      viewModel.ensureLoaded(libraryIds: effectiveLibraryIds)
    }
    .onDisappear {
      DashboardRefreshCoordinator.shared.unregisterSection(section)
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
          viewModel.removeItem(id: itemId)
        }
      )
    case .series:
      SeriesQueryItemView(
        seriesId: itemId,
        layout: .grid,
        coverOnly: cardKind == .small,
        cardWidth: itemWidth,
        onItemMissing: {
          viewModel.removeItem(id: itemId)
        }
      )
    }
  }

  private func handleReloadCommand(_ command: DashboardSectionReloadCommand) {
    guard command.includes(section) else {
      logger.debug("Dashboard section \(section) skipping reload: targeted other sections")
      return
    }

    if command.source == .auto, viewModel.pagination.currentPage > 1 {
      logger.debug(
        "Dashboard section \(section) skipping auto-refresh: deep in pagination (page \(viewModel.pagination.currentPage))"
      )
      return
    }

    let libraryIds = effectiveLibraryIds
    Task {
      logger.debug("Dashboard section \(section) reloading")
      defer {
        DashboardRefreshCoordinator.shared.acknowledgeSectionReload(
          commandID: command.id, section: section)
      }
      await viewModel.reload(libraryIds: libraryIds)
    }
  }
}
