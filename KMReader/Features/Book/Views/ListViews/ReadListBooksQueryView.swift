//
// ReadListBooksQueryView.swift
//
//

import SwiftUI

struct ReadListBooksQueryView: View {
  let readListId: String
  let readListContext: ReaderReadListContext?
  @Bindable var bookViewModel: BookViewModel
  let browseOpts: ReadListBookBrowseOptions
  let browseLayout: BrowseLayoutMode
  let isSelectionMode: Bool
  @Binding var selectedBookIds: Set<String>
  let isAdmin: Bool

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  init(
    readListId: String,
    readListContext: ReaderReadListContext?,
    bookViewModel: BookViewModel,
    browseOpts: ReadListBookBrowseOptions,
    browseLayout: BrowseLayoutMode,
    isSelectionMode: Bool,
    selectedBookIds: Binding<Set<String>>,
    isAdmin: Bool
  ) {
    self.readListId = readListId
    self.readListContext = readListContext
    self.bookViewModel = bookViewModel
    self.browseOpts = browseOpts
    self.browseLayout = browseLayout
    self.isSelectionMode = isSelectionMode
    self._selectedBookIds = selectedBookIds
    self.isAdmin = isAdmin
  }

  var body: some View {
    Group {
      if bookViewModel.isLoading && bookViewModel.pagination.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      } else {
        switch browseLayout {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(bookViewModel.pagination.items) { book in
              Group {
                if isSelectionMode && isAdmin {
                  BookSelectionItemView(
                    bookId: book.id,
                    layout: browseLayout,
                    selectedBookIds: $selectedBookIds,
                    cardWidth: browseLayout.cardWidth,
                    showSeriesTitle: true
                  )
                } else {
                  BookQueryItemView(
                    bookId: book.id,
                    layout: browseLayout,
                    showSeriesTitle: true,
                    readListContext: readListContext,
                    cardWidth: browseLayout.cardWidth,
                    onItemMissing: {
                      bookViewModel.removeBook(id: book.id)
                    }
                  )
                }
              }
              .onAppear {
                if bookViewModel.pagination.shouldLoadMore(after: book) {
                  Task { await loadMore(refresh: false) }
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(bookViewModel.pagination.items) { book in
              Group {
                if isSelectionMode && isAdmin {
                  BookSelectionItemView(
                    bookId: book.id,
                    layout: .list,
                    selectedBookIds: $selectedBookIds,
                    showSeriesTitle: true
                  )
                } else {
                  BookQueryItemView(
                    bookId: book.id,
                    layout: .list,
                    showSeriesTitle: true,
                    readListContext: readListContext,
                    onItemMissing: {
                      bookViewModel.removeBook(id: book.id)
                    }
                  )
                }
              }
              .onAppear {
                if bookViewModel.pagination.shouldLoadMore(after: book) {
                  Task { await loadMore(refresh: false) }
                }
              }
              if !bookViewModel.pagination.isLast(book) {
                Divider()
              }
            }
          }
          .padding(.horizontal)
        }
      }
    }
  }

  private func loadMore(refresh: Bool) async {
    await bookViewModel.loadReadListBooks(
      readListId: readListId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }
}
