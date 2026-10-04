//
// SeriesCardView.swift
//
//

import SwiftUI

struct SeriesCardView: View {
  let item: SeriesDisplayItem
  var onMutationCompleted: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil
  var showUnreadIndicator: Bool = true
  /// Small dashboard cards are cover-only: at that width every text line
  /// truncates and stops carrying information.
  var coverOnly: Bool = false
  /// Text styles and the corner badge scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @AppStorage("thumbnailShowUnreadIndicator") private var thumbnailShowUnreadIndicator: Bool = true

  @State private var showCollectionPicker = false
  @State private var showEditSheet = false
  @State private var showKomfIdentify = false

  var progress: Double {
    guard item.booksCount > 0 else { return 0 }
    return Double(item.booksReadCount) / Double(item.booksCount)
  }

  private var badgeSize: CGFloat {
    LayoutConfig.cardBadgeSize(cardWidth: cardWidth)
  }

  private var tertiaryTextStyle: Font.TextStyle {
    LayoutConfig.cardTextStyle(cardWidth: cardWidth).tertiary
  }

  var body: some View {
    GridCardView(
      thumbnailId: item.seriesId,
      thumbnailType: .series,
      title: item.metaTitle,
      coverOnly: coverOnly,
      cardWidth: cardWidth,
      isUnread: item.isUnread,
      navigationLink: item.navDestination,
      downloadIcon: item.downloadStatus.icon,
      downloadSpinning: item.downloadStatus.isPending
    ) {
      if thumbnailShowUnreadIndicator && showUnreadIndicator && item.booksUnreadCount > 0 {
        VStack(alignment: .trailing) {
          UnreadCountBadge(count: item.booksUnreadCount, size: badgeSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .transition(.scale(scale: 0).combined(with: .opacity))
        .animation(.appSpring, value: item.booksUnreadCount > 0)
      }
    } menu: {
      SeriesContextMenu(
        seriesId: item.seriesId,
        libraryId: item.series.libraryId,
        seriesTitle: item.metaTitle,
        downloadStatus: item.downloadStatus,
        offlinePolicy: item.offlinePolicy,
        offlinePolicyLimit: item.offlinePolicyLimit,
        booksUnreadCount: item.booksUnreadCount,
        booksReadCount: item.booksReadCount,
        booksInProgressCount: item.booksInProgressCount,
        onShowCollectionPicker: {
          #if os(macOS)
            // Present in a standalone window: a view-attached sheet
            // triggered from an NSMenu action can wedge the app on
            // macOS 15.
            PickerWindowOpener.shared.open(.collection(seriesId: item.seriesId))
          #else
            showCollectionPicker = true
          #endif
        },
        onDeleteRequested: onDeleteRequested,
        onEditRequested: {
          showEditSheet = true
        },
        onKomfIdentifyRequested: {
          showKomfIdentify = true
        },
        onMutationCompleted: onMutationCompleted
      )
    } detail: {
      statusContent(overlay: false)
    } overlayDetail: {
      statusContent(overlay: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesId: item.seriesId,
        onSelect: { collectionId in
          addToCollection(collectionId: collectionId)
        }
      )
    }
    .sheet(isPresented: $showEditSheet) {
      SeriesEditSheet(series: item.series)
    }
    .sheet(isPresented: $showKomfIdentify) {
      KomfIdentifySheet(series: item.series)
    }
  }

  @ViewBuilder
  private func statusContent(overlay: Bool) -> some View {
    if item.isUnavailable {
      Text("Unavailable")
        .foregroundColor(.red)
    } else {
      if progress > 0 && progress < 1 {
        Text(progress, format: .percent.precision(.fractionLength(0)))
        Text("•")
      }
      if progress == 1 {
        Image(systemName: "checkmark.circle")
          .foregroundColor(overlay ? CardOverlayTextStyle.standard.secondaryColor : .secondary)
          .font(overlay ? .caption2 : .system(tertiaryTextStyle))
      }
      if item.oneshot {
        Label(item.oneshotLine, systemImage: "book.closed")
          .labelStyle(.compact)
          .lineLimit(1)
      } else {
        Text("\(item.booksCount) books")
          .lineLimit(1)
      }
    }
  }

  private func addToCollection(collectionId: String) {
    Task {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: collectionId,
          seriesIds: [item.seriesId]
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

}
