//
// BookRowView.swift
//
//

import SwiftUI

struct BookRowView: View {
  let item: BookDisplayItem
  var onReadBook: ((Bool) -> Void)?
  var onMutationCompleted: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil
  var showSeriesTitle: Bool = false
  var showSeriesNavigation: Bool = true
  /// Selection mode hides the menu: the row's only interaction is toggling.
  var showsEllipsis: Bool = true

  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  @State private var showReadListPicker = false
  @State private var showEditSheet = false

  var shouldShowSeriesTitle: Bool {
    return showSeriesTitle && !item.seriesTitle.isEmpty
  }

  var bookTitleLineLimit: Int {
    (shouldShowSeriesTitle || item.oneshot) ? 1 : 2
  }

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && item.isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  var body: some View {
    HStack(spacing: 12) {
      Button {
        onReadBook?(false)
      } label: {
        ThumbnailImage(
          id: item.bookId,
          type: .book,
          contentBlurRadius: coverBlurRadius,
          width: 60
        )
      }.adaptiveButtonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Button {
          onReadBook?(false)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            if item.oneshot {
              Label(item.oneshotLine, systemImage: "book.closed")
                .labelStyle(.compact)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
            } else if shouldShowSeriesTitle {
              Text(item.seriesTitle)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Text("#\(item.metaNumber) - \(item.metaTitle)")
              .foregroundColor(item.isCompleted ? .secondary : .primary)
              .lineLimit(bookTitleLineLimit)
          }
        }.adaptiveButtonStyle(.plain)

        HStack {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
              if let releaseDate = item.metaReleaseDate, !releaseDate.isEmpty {
                Text(releaseDate)
              } else {
                Text(item.created.formatted(date: .abbreviated, time: .omitted))
              }
              if let progressPage = item.progressPage,
                let progressCompleted = item.progressCompleted
              {
                Text("•")
                if progressCompleted {
                  Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                  if let completedLastReadText = item.completedLastReadText {
                    Text(completedLastReadText)
                  }
                } else {
                  Image(systemName: "circle.righthalf.filled")
                    .foregroundColor(.orange)
                  Text("Page \(progressPage + 1)")
                    .foregroundColor(.orange)
                  Text("•")
                  Text(item.progress, format: .percent.precision(.fractionLength(0)))
                }
              }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)

            HStack(spacing: 4) {
              let mediaStatus = item.media.statusValue
              if item.isUnavailable {
                Text("Unavailable")
                  .foregroundColor(.red)
              } else if mediaStatus != .ready {
                Text(mediaStatus.label)
                  .foregroundColor(mediaStatus.color)
              } else {
                Text("\(item.mediaPagesCount) pages")
                  .foregroundColor(.secondary)
                Text("•").foregroundColor(.secondary)
                Text(item.size)
                  .foregroundColor(.secondary)
              }
            }
            .font(.footnote)
            .lineLimit(1)
          }

          Spacer()

          if let icon = item.downloadStatus.displayIcon {
            DownloadStatusIcon(
              systemName: icon, spinning: item.downloadStatus.isPending,
              color: item.downloadStatus.displayColor, bookId: item.bookId)
          }
          if showsEllipsis {
            EllipsisMenuButton {
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
              .id(item.bookId)
            }
          }
        }
      }
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
