//
// ReadListContinuationCardView.swift
//
//

import SwiftUI

/// Large or small card for a read list the user is reading: the next book's
/// cover and progress, the read list's name in the series slot, the book's
/// title, and how far along the list is. Opens the next book in the read
/// list's order.
struct ReadListContinuationCardView: View {
  let continuation: ReadListContinuation
  /// Small dashboard cards are cover-only: at that width every text line
  /// truncates and stops carrying information.
  var coverOnly: Bool = false
  /// Text styles scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @Environment(\.readerActions) private var readerActions

  /// The book a list continues with is in progress or unread; only a book in
  /// progress has progress.
  private var isInProgress: Bool {
    continuation.bookProgress != nil
  }

  var body: some View {
    GridCardView(
      thumbnailId: continuation.bookId,
      thumbnailType: .book,
      title: continuation.bookTitle,
      coverOnly: coverOnly,
      cardWidth: cardWidth,
      isUnread: !isInProgress,
      onAction: { readerActions.open(continuation: continuation) },
      subtitle: continuation.readListName,
      downloadIcon: continuation.downloadStatus.displayIcon,
      downloadSpinning: continuation.downloadStatus.isPending,
      downloadColor: continuation.downloadStatus.failureColor,
      progress: continuation.bookProgress ?? 0,
      isInProgress: isInProgress
    ) {
      ReadListContinuationContextMenu(continuation: continuation)
    } detail: {
      ReadListContinuationProgressText(continuation: continuation)
        .lineLimit(1)
    } overlayDetail: {
      ReadListContinuationProgressText(continuation: continuation)
        .lineLimit(1)
    }
  }
}
