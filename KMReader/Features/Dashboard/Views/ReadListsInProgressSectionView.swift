//
// ReadListsInProgressSectionView.swift
//
//

import SwiftUI

/// Dashboard row of the read lists the user is reading, one card per list with
/// the book it continues with. Driven by `ReadListReadingService`'s published
/// snapshot, so it needs no loading or pagination of its own.
@MainActor
struct ReadListsInProgressSectionView: View {
  let section: DashboardSection

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  private let logger = AppLogger(.dashboard)

  /// The library scope hides entries by the library of the book each list
  /// continues with; which book that is never depends on the scope.
  private var continuations: [ReadListContinuation] {
    let librarySelection = Set(dashboard.libraryIds)
    return ReadListReadingService.shared.continuations.filter {
      librarySelection.isEmpty || librarySelection.contains($0.libraryId)
    }
  }

  private var cardKind: DashboardCardKind {
    dashboard.cardKind(for: section)
  }

  var body: some View {
    DashboardSectionLayout(
      section: section,
      destination: .browseReadLists,
      showsCardKindMenu: true,
      isEmpty: continuations.isEmpty,
      itemIds: continuations.map(\.readListId)
    ) {
      LazyHStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
        ForEach(continuations, id: \.readListId) { continuation in
          continuationCard(continuation)
            .id(continuation.readListId)
            .frame(width: cardKind.cardWidth)
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dashboardSectionsShouldReload)) {
      notification in
      guard let command = DashboardSectionRefreshNotifier.reloadCommand(from: notification),
        command.includes(section)
      else { return }
      handleReloadCommand(command)
    }
    .onAppear {
      DashboardRefreshCoordinator.shared.registerSection(section)
    }
    .onDisappear {
      DashboardRefreshCoordinator.shared.unregisterSection(section)
    }
  }

  @ViewBuilder
  private func continuationCard(_ continuation: ReadListContinuation) -> some View {
    switch cardKind {
    case .horizontal:
      ReadListContinuationHorizontalCardView(
        continuation: continuation,
        coverWidth: LayoutConfig.horizontalCoverWidth
      )
    case .large, .medium, .small:
      ReadListContinuationCardView(
        continuation: continuation,
        coverOnly: cardKind == .small,
        cardWidth: cardKind.cardWidth
      )
    }
  }

  /// A manual refresh also pulls other devices' changes; other reloads only
  /// re-derive from local data, which the other sections just refreshed.
  private func handleReloadCommand(_ command: DashboardSectionReloadCommand) {
    let instanceId = AppConfig.current.instanceId
    Task {
      logger.debug("Dashboard section \(section) reloading")
      defer {
        DashboardRefreshCoordinator.shared.acknowledgeSectionReload(
          commandID: command.id, section: section)
      }
      if command.source == .manual {
        await ReadListReadingService.shared.sync(instanceId: instanceId)
      } else {
        await ReadListReadingService.shared.refreshSnapshot()
      }
    }
  }
}
