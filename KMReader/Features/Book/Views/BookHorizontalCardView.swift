//
// BookHorizontalCardView.swift
//
//

import SwiftUI

/// Horizontal book card: cover on the left,
/// title/series/progress on the right, inside a rounded material card.
struct BookHorizontalCardView: View {
  let item: BookDisplayItem
  var coverWidth: CGFloat = 45
  var onReadBook: ((Bool) -> Void)? = nil
  var onMutationCompleted: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil
  var showSeriesNavigation: Bool = true

  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false
  @State private var showReadListPicker = false
  @State private var showEditSheet = false

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && item.isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  private var bookContextMenu: some View {
    BookContextMenu(
      book: item.book,
      downloadStatus: item.downloadStatus,
      onReadBook: onReadBook,
      onShowReadListPicker: {
        #if os(macOS)
          // Present in a standalone window: a view-attached sheet triggered
          // from an NSMenu action can wedge the app on macOS 15.
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
  }

  var body: some View {
    HorizontalCardSkeleton(
      thumbnailId: item.bookId,
      thumbnailType: .book,
      coverWidth: coverWidth,
      shadowStyle: .platform,
      contentBlurRadius: coverBlurRadius,
      onAction: {
        onReadBook?(false)
      },
      downloadIcon: item.downloadStatus.displayIcon,
      downloadSpinning: item.downloadStatus.isPending,
      downloadColor: item.downloadStatus.failureColor
    ) { palette in
      Spacer(minLength: 0)

      Text(item.bookTitleLine)
        .font(.system(size: LayoutConfig.horizontalCardFontSize, weight: .semibold))
        .foregroundColor(titleColor(palette: palette))
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .padding(.bottom, 4)

      if item.oneshot {
        Label(item.oneshotLine, systemImage: "book.closed")
          .labelStyle(.compact)
          .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))
          .foregroundColor(palette.seriesColor)
          .lineLimit(1)
      } else if !item.seriesTitle.isEmpty {
        Text(item.seriesTitle)
          .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))
          .foregroundColor(palette.seriesColor)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      bottomBar(palette: palette)

      Spacer(minLength: 0)
    } menu: {
      bookContextMenu
    }
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookIds: [item.bookId],
        onSelect: { readListId in
          addToReadList(readListId: readListId)
        }
      )
    }
    .sheet(isPresented: $showEditSheet) {
      BookEditSheet(book: item.book)
    }
  }

  private func titleColor(palette: HorizontalCardPalette) -> Color {
    if palette.isTinted { return item.isCompleted ? .white.opacity(0.7) : .white }
    return item.isCompleted ? .secondary : .primary
  }

  @ViewBuilder
  private func bottomBar(palette: HorizontalCardPalette) -> some View {
    HStack(spacing: 4) {
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
            .foregroundColor(palette.metaColor)
            .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
        }
        Text(item.progress == 1 ? item.completedMetaText : "\(item.mediaPagesCount) pages")
      }
    }
    .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
    .foregroundColor(palette.metaColor)
    .lineLimit(1)
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
