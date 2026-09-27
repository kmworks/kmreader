//
// BookQueryItemView.swift
//
//

import SwiftUI

/// Wrapper view that accepts only bookId and fetches a book display projection.
struct BookQueryItemView: View {
  let bookId: String
  let layout: BrowseLayoutMode
  var showSeriesTitle: Bool = true
  var showSeriesNavigation: Bool = true
  var readListContext: ReaderReadListContext? = nil
  var horizontalCoverWidth: CGFloat? = nil
  var coverOnly: Bool = false
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth
  var onItemMissing: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @Environment(\.readerActions) private var readerActions
  @State private var item: BookDisplayItem?
  @State private var showDeleteConfirmation = false

  init(
    bookId: String,
    layout: BrowseLayoutMode,
    showSeriesTitle: Bool = true,
    showSeriesNavigation: Bool = true,
    readListContext: ReaderReadListContext? = nil,
    horizontalCoverWidth: CGFloat? = nil,
    coverOnly: Bool = false,
    cardWidth: CGFloat = LayoutConfig.gridCardWidth,
    onItemMissing: (() -> Void)? = nil
  ) {
    self.bookId = bookId
    self.layout = layout
    self.showSeriesTitle = showSeriesTitle
    self.showSeriesNavigation = showSeriesNavigation
    self.readListContext = readListContext
    self.horizontalCoverWidth = horizontalCoverWidth
    self.coverOnly = coverOnly
    self.cardWidth = cardWidth
    self.onItemMissing = onItemMissing

  }

  var body: some View {
    Group {
      if let item {
        if let horizontalCoverWidth, layout == .grid {
          BookHorizontalCardView(
            item: item,
            coverWidth: horizontalCoverWidth,
            onReadBook: { incognito in
              readerActions.open(
                book: item.book,
                incognito: incognito,
                readListContext: readListContext
              )
            },
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            },
            showSeriesNavigation: showSeriesNavigation
          )
        } else {
          switch layout {
          case .grid, .largeGrid:
            BookCardView(
              item: item,
              onReadBook: { incognito in
                readerActions.open(
                  book: item.book,
                  incognito: incognito,
                  readListContext: readListContext
                )
              },
              onMutationCompleted: reloadItem,
              onDeleteRequested: {
                showDeleteConfirmation = true
              },
              showSeriesTitle: showSeriesTitle,
              showSeriesNavigation: showSeriesNavigation,
              coverOnly: coverOnly,
              cardWidth: cardWidth
            )
          case .list:
            BookRowView(
              item: item,
              onReadBook: { incognito in
                readerActions.open(
                  book: item.book,
                  incognito: incognito,
                  readListContext: readListContext
                )
              },
              onMutationCompleted: reloadItem,
              onDeleteRequested: {
                showDeleteConfirmation = true
              },
              showSeriesTitle: showSeriesTitle,
              showSeriesNavigation: showSeriesNavigation
            )
          }
        }
      } else {
        if let horizontalCoverWidth, layout == .grid {
          BookHorizontalCardPlaceholder(coverWidth: horizontalCoverWidth)
        } else {
          CardPlaceholder(
            layout: layout,
            kind: .book,
            showBookSeriesTitle: showSeriesTitle,
            cardWidth: cardWidth,
            coverOnly: coverOnly
          )
        }
      }
    }
    .task(id: "\(current.instanceId)|\(bookId)") {
      await loadItem()
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) {
      notification in
      guard shouldReload(for: notification) else { return }
      reloadItem()
    }
    .alert("Delete Book", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteBook()
      }
    } message: {
      Text("Are you sure you want to delete this book? This action cannot be undone.")
    }
  }

  private func shouldReload(for notification: Notification) -> Bool {
    if notification.userInfo?["bookId"] as? String == bookId {
      return true
    }
    if let bookIds = notification.userInfo?["bookIds"] as? Set<String> {
      return bookIds.contains(bookId)
    }
    if let bookIds = notification.userInfo?["bookIds"] as? [String] {
      return bookIds.contains(bookId)
    }
    return false
  }

  private func reloadItem() {
    Task {
      await loadItem()
    }
  }

  private func deleteBook() {
    Task {
      do {
        if let item {
          try await BookDeletionService.deleteBook(item)
        } else {
          try await BookDeletionService.deleteBook(bookId: bookId, instanceId: current.instanceId)
        }
        ErrorManager.shared.notify(message: String(localized: "notification.book.deleted"))
        await loadItem()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func loadItem() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      return
    }
    let loadedItem = try? await database.fetchBookDisplayItem(
      bookId: bookId,
      instanceId: current.instanceId
    )
    item = loadedItem
    if loadedItem == nil {
      onItemMissing?()
    }
  }
}
