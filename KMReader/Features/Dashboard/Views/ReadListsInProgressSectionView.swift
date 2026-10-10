//
// ReadListsInProgressSectionView.swift
//
//

import SwiftUI

/// Dashboard row of the read lists the user is reading, one card per list with
/// the book it continues with. Pure renderer driven by `ReadListReadingService`'s
/// published snapshot; reloads are dispatched by `DashboardViewModel`.
@MainActor
struct ReadListsInProgressSectionView: View {
  let section: DashboardSection

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

  /// The library scope hides entries by the library of the book each list
  /// continues with; which book that is never depends on the scope.
  private var continuations: [ReadListContinuation] {
    let librarySelection = Set(
      DashboardLibraryScopeStore.shared.effectiveLibraryIds(pinned: dashboard.libraryIds))
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
      destination: .browseReadLists(scope: DashboardLibraryScopeStore.shared.scope),
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
}
