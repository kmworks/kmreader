//
// SeriesBooksQueryView.swift
//
//

import SwiftUI

struct SeriesBooksQueryView: View {
  let seriesId: String
  let bookViewModel: BookViewModel
  let browseOpts: BookBrowseOptions
  let browseLayout: BrowseLayoutMode
  let isSelectionMode: Bool
  @Binding var selectedBookIds: Set<String>
  let refreshBooks: () -> Void

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  init(
    seriesId: String,
    bookViewModel: BookViewModel,
    browseOpts: BookBrowseOptions,
    browseLayout: BrowseLayoutMode,
    isSelectionMode: Bool,
    selectedBookIds: Binding<Set<String>>,
    refreshBooks: @escaping () -> Void
  ) {
    self.seriesId = seriesId
    self.bookViewModel = bookViewModel
    self.browseOpts = browseOpts
    self.browseLayout = browseLayout
    self.isSelectionMode = isSelectionMode
    self._selectedBookIds = selectedBookIds
    self.refreshBooks = refreshBooks
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
                if isSelectionMode {
                  BookSelectionItemView(
                    bookId: book.id,
                    layout: browseLayout,
                    selectedBookIds: $selectedBookIds,
                    refreshBooks: refreshBooks,
                    showSeriesTitle: false
                  )
                } else {
                  BookQueryItemView(
                    bookId: book.id,
                    layout: browseLayout,
                    showSeriesTitle: false,
                    showSeriesNavigation: false,
                    cardWidth: browseLayout.cardWidth,
                    onItemMissing: {
                      bookViewModel.removeBook(id: book.id)
                    }
                  )
                }
              }
              .padding(.bottom)
              .onAppear {
                if bookViewModel.pagination.shouldLoadMore(after: book) {
                  loadBooks(refresh: false)
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(bookViewModel.pagination.items) { book in
              Group {
                if isSelectionMode {
                  BookSelectionItemView(
                    bookId: book.id,
                    layout: .list,
                    selectedBookIds: $selectedBookIds,
                    refreshBooks: refreshBooks,
                    showSeriesTitle: false
                  )
                } else {
                  BookQueryItemView(
                    bookId: book.id,
                    layout: .list,
                    showSeriesTitle: false,
                    showSeriesNavigation: false,
                    onItemMissing: {
                      bookViewModel.removeBook(id: book.id)
                    }
                  )
                }
              }
              .onAppear {
                if bookViewModel.pagination.shouldLoadMore(after: book) {
                  loadBooks(refresh: false)
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

  private func loadBooks(refresh: Bool) {
    Task {
      await bookViewModel.loadSeriesBooks(
        seriesId: seriesId,
        browseOpts: browseOpts,
        refresh: refresh
      )
    }
  }
}
