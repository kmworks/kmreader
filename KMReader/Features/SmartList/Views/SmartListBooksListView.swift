//
// SmartListBooksListView.swift
//
//

import SwiftUI

struct SmartListBooksListView: View {
  let smartListId: String

  @AppStorage("smartListBookBrowseLayout") private var layoutMode: BrowseLayoutMode = .list
  @AppStorage("smartListBookBrowseOptions") private var browseOpts: BookBrowseOptions =
    BookBrowseOptions()

  @State private var bookViewModel = BookViewModel()
  @State private var showFilterSheet = false
  @State private var loadedSmartListId: String?

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: layoutMode.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        BookFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: .constant(false),
          showsPresets: false,
          layoutMode: $layoutMode
        )
      }
      .padding(.horizontal)

      BrowseStateView(
        isLoading: bookViewModel.isLoading,
        isEmpty: bookViewModel.pagination.isEmpty,
        emptyIcon: ContentIcon.book,
        emptyTitle: LocalizedStringKey("No books found"),
        emptyMessage: LocalizedStringKey("Try adjusting the filters."),
        onRetry: {
          Task { await loadBooks(refresh: true) }
        }
      ) {
        switch layoutMode {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(bookViewModel.pagination.items) { book in
              BookQueryItemView(
                bookId: book.id,
                layout: layoutMode,
                showSeriesTitle: true,
                cardWidth: layoutMode.cardWidth,
                onItemMissing: {
                  bookViewModel.removeBook(id: book.id)
                }
              )
              .onAppear {
                if bookViewModel.pagination.shouldLoadMore(after: book) {
                  Task { await loadBooks(refresh: false) }
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(bookViewModel.pagination.items) { book in
              BookQueryItemView(
                bookId: book.id,
                layout: .list,
                showSeriesTitle: true,
                onItemMissing: {
                  bookViewModel.removeBook(id: book.id)
                }
              )
              .onAppear {
                if bookViewModel.pagination.shouldLoadMore(after: book) {
                  Task { await loadBooks(refresh: false) }
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
    .task(id: smartListId) {
      guard loadedSmartListId != smartListId else { return }
      loadedSmartListId = smartListId
      await loadBooks(refresh: true)
    }
    .onChange(of: browseOpts) {
      Task {
        await loadBooks(refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) { _ in
      Task { await revalidateBooks() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListMembershipDidChange)) { _ in
      Task { await revalidateBooks() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListsDidChange)) { notification in
      guard notification.userInfo?["smartListId"] as? String == smartListId else { return }
      Task { await revalidateBooks() }
    }
  }

  private func loadBooks(refresh: Bool) async {
    await bookViewModel.loadSmartListBooks(
      smartListId: smartListId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }

  /// The stored server-side filter may be read-status-based even when the
  /// overlay options are not, so every book change revalidates the window.
  private func revalidateBooks() async {
    await bookViewModel.revalidateSmartListBooks(
      smartListId: smartListId,
      browseOpts: browseOpts
    )
  }
}
