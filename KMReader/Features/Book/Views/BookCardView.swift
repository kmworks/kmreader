//
// BookCardView.swift
//
//

import SwiftUI

struct BookCardView: View {
  let item: BookDisplayItem
  var onReadBook: ((Bool) -> Void)? = nil
  var onMutationCompleted: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil
  var showSeriesTitle: Bool = false
  var showSeriesNavigation: Bool = true
  var showCompletedIndicator: Bool = true
  /// Small dashboard cards are cover-only: at that width every text line
  /// truncates and stops carrying information.
  var coverOnly: Bool = false
  /// Text styles and the corner badge scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @AppStorage("showBookCardSeriesTitle") private var showBookCardSeriesTitle: Bool = true
  @AppStorage("thumbnailShowUnreadIndicator") private var thumbnailShowUnreadIndicator: Bool = true
  @State private var showReadListPicker = false
  @State private var showEditSheet = false

  var shouldShowSeriesTitle: Bool {
    return showSeriesTitle && showBookCardSeriesTitle && !item.seriesTitle.isEmpty
  }

  var bookTitleLineLimit: Int {
    (shouldShowSeriesTitle || item.oneshot) ? 1 : 2
  }

  private var subtitle: String? {
    if item.oneshot {
      return item.oneshotLine
    }
    return shouldShowSeriesTitle ? item.seriesTitle : nil
  }

  private var subtitleLeadingSystemImage: String? {
    item.oneshot ? "book.closed" : nil
  }

  private var badgeSize: CGFloat {
    LayoutConfig.cardBadgeSize(cardWidth: cardWidth)
  }

  private var tertiaryTextStyle: Font.TextStyle {
    LayoutConfig.cardTextStyle(cardWidth: cardWidth).tertiary
  }

  var body: some View {
    GridCardView(
      thumbnailId: item.bookId,
      thumbnailType: .book,
      title: item.bookTitleLine,
      coverOnly: coverOnly,
      cardWidth: cardWidth,
      isUnread: item.isUnread,
      onAction: { onReadBook?(false) },
      titleLineLimit: bookTitleLineLimit,
      subtitle: subtitle,
      subtitleLeadingSystemImage: subtitleLeadingSystemImage,
      downloadIcon: item.downloadStatus.displayIcon,
      downloadSpinning: item.downloadStatus.isPending,
      downloadColor: item.downloadStatus.failureColor,
      progress: item.progress,
      isInProgress: item.isInProgress
    ) {
      if item.isCompleted && thumbnailShowUnreadIndicator && showCompletedIndicator {
        CompletedIndicator(size: badgeSize)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }
    } menu: {
      BookContextMenu(
        book: item.book,
        downloadStatus: item.downloadStatus,
        onReadBook: onReadBook,
        onShowReadListPicker: {
          #if os(macOS)
            // Present in a standalone window: a view-attached sheet
            // triggered from an NSMenu action can wedge the app on
            // macOS 15.
            PickerWindowOpener.shared.open(.readList(bookId: item.bookId))
          #else
            showReadListPicker = true
          #endif
        },
        onDeleteRequested: onDeleteRequested,
        onEditRequested: {
          showEditSheet = true
        },
        onMutationCompleted: onMutationCompleted,
        showSeriesNavigation: showSeriesNavigation
      )
    } detail: {
      statusContent(overlay: false)
    } overlayDetail: {
      statusContent(overlay: true)
    }
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookId: item.bookId,
        onSelect: { readListId in
          addToReadList(readListId: readListId)
        }
      )
    }
    .sheet(isPresented: $showEditSheet) {
      BookEditSheet(book: item.book)
    }
  }

  @ViewBuilder
  private func statusContent(overlay: Bool) -> some View {
    let mediaStatus = item.media.statusValue
    if item.isUnavailable {
      Text("Unavailable")
        .foregroundColor(.red)
    } else if mediaStatus != .ready {
      Text(mediaStatus.label)
        .foregroundColor(mediaStatus.color)
    } else {
      if item.progress > 0 && item.progress < 1 {
        Text(item.progress, format: .percent.precision(.fractionLength(0)))
        Text("•")
      }
      if item.progress == 1 {
        Image(systemName: "checkmark.circle")
          .foregroundColor(overlay ? CardOverlayTextStyle.standard.secondaryColor : .secondary)
          .font(overlay ? .caption2 : .system(tertiaryTextStyle))
      }
      Text(item.progress == 1 ? item.completedMetaText : "\(item.mediaPagesCount) pages")
        .lineLimit(1)
    }
  }

  private func addToReadList(readListId: String) {
    Task {
      do {
        try await ReadListService.addBooksToReadList(
          readListId: readListId,
          bookIds: [item.bookId]
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

}
