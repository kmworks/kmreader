//
// ReadListContinuationHorizontalCardView.swift
//
//

import SwiftUI

/// Horizontal card for a read list the user is reading: the next book's cover,
/// the read list's name, and how far along the list is. Opens the next book in
/// the read list's order.
@MainActor
struct ReadListContinuationHorizontalCardView: View {
  let continuation: ReadListContinuation
  var coverWidth: CGFloat = 56

  @Environment(\.readerActions) private var readerActions

  private var continuationContextMenu: some View {
    ReadListContinuationContextMenu(continuation: continuation)
  }

  var body: some View {
    HorizontalCardSkeleton(
      thumbnailId: continuation.bookId,
      thumbnailType: .book,
      coverWidth: coverWidth,
      shadowStyle: .platform,
      onAction: {
        readerActions.open(continuation: continuation)
      },
      downloadIcon: continuation.downloadStatus.displayIcon,
      downloadSpinning: continuation.downloadStatus.isPending,
      downloadColor: continuation.downloadStatus.displayColor
    ) { palette in
      Spacer(minLength: 0)

      Text(continuation.readListName)
        .font(.system(size: LayoutConfig.horizontalCardFontSize, weight: .semibold))
        .foregroundColor(palette.titleColor)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: 4) {
        Text(continuation.bookTitle)
          .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))
          .foregroundColor(palette.seriesColor)
          .lineLimit(1)

        ReadListContinuationProgressText(continuation: continuation)
          .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
          .lineLimit(1)
      }
      .foregroundColor(palette.metaColor)

      Spacer(minLength: 0)
    } menu: {
      continuationContextMenu
    }
  }
}
