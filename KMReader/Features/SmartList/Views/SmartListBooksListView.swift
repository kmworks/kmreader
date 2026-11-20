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
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var bookViewModel = BookViewModel()
  @State private var showFilterSheet = false
  @State private var loadedSmartListId: String?
  @State private var selectedBookIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showReadListPicker = false
  @State private var showBatchEditor = false
  @State private var showDeleteConfirmation = false

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: layoutMode.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  private var supportsSelectionMode: Bool {
    #if os(tvOS)
      return false
    #else
      return true
    #endif
  }

  private var loadedBookIds: [String] {
    bookViewModel.pagination.items.map(\.id)
  }

  private var selectedBookIdsInDisplayOrder: [String] {
    loadedBookIds.filter(selectedBookIds.contains)
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

        if supportsSelectionMode && !isSelectionMode && !isOffline {
          Button {
            withAnimation { isSelectionMode = true }
          } label: {
            Image(systemName: "checkmark.circle")
          }
          .adaptiveButtonStyle(.bordered)
          .optimizedControlSize()
        }
      }
      .padding(.horizontal)

      if supportsSelectionMode && isSelectionMode {
        SelectionActionsToolbar(
          selectedCount: selectedBookIds.count,
          totalCount: loadedBookIds.count,
          isSubmitting: batchController.isRunning,
          completedCount: batchController.completedCount,
          runningTotalCount: batchController.totalCount,
          addLabel: String(localized: "Add to Read List"),
          editLabel: String(localized: "Edit Metadata"),
          deleteLabel: current.isAdmin ? String(localized: "Delete Files") : nil,
          komfMatchLabel: nil,
          onSelectAll: toggleSelectAll,
          onMarkRead: {
            Task { await markSelected(read: true) }
          },
          onMarkUnread: {
            Task { await markSelected(read: false) }
          },
          onAdd: { showReadListPicker = true },
          onEdit: { showBatchEditor = true },
          onDelete: { showDeleteConfirmation = true },
          onKomfMatch: {},
          onCancel: exitSelectionMode
        )
        .padding(.horizontal)
      }

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
              Group {
                if isSelectionMode {
                  BookSelectionItemView(
                    bookId: book.id,
                    layout: layoutMode,
                    selectedBookIds: $selectedBookIds,
                    cardWidth: layoutMode.cardWidth,
                    showSeriesTitle: true
                  )
                } else {
                  BookQueryItemView(
                    bookId: book.id,
                    layout: layoutMode,
                    showSeriesTitle: true,
                    cardWidth: layoutMode.cardWidth,
                    onItemMissing: {
                      bookViewModel.removeBook(id: book.id)
                    }
                  )
                }
              }
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
              Group {
                if isSelectionMode {
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
                    onItemMissing: {
                      bookViewModel.removeBook(id: book.id)
                    }
                  )
                }
              }
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
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookIds: selectedBookIdsInDisplayOrder,
        onSelect: addSelectedToReadList,
        onCreate: { _ in finishBatchSelection([]) }
      )
    }
    .sheet(isPresented: $showBatchEditor) {
      BookBatchEditSheet(
        bookIds: selectedBookIdsInDisplayOrder,
        onCompleted: finishBatchSelection
      )
    }
    .alert("Delete Book Files", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task { await deleteSelectedFiles() }
      }
    } message: {
      Text("batch.books.deleteConfirmation \(selectedBookIds.count)")
    }
  }

  private func toggleSelectAll() {
    if selectedBookIds.count == loadedBookIds.count {
      selectedBookIds.removeAll()
    } else {
      selectedBookIds = Set(loadedBookIds)
    }
  }

  private func markSelected(read: Bool) async {
    guard !selectedBookIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await BookBatchActions.mark(
      ids: Array(selectedBookIds),
      read: read,
      instanceId: current.instanceId,
      using: batchController
    )
    finishBatchSelection(Set(outcome.failed))
  }

  private func addSelectedToReadList(readListId: String) {
    let bookIds = selectedBookIdsInDisplayOrder
    guard !bookIds.isEmpty else { return }

    Task {
      do {
        try await ReadListService.addBooksToReadList(readListId: readListId, bookIds: bookIds)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        await ContentProjectionNotifier.postReadListDidChange(readListId: readListId)
        finishBatchSelection([])
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deleteSelectedFiles() async {
    guard !selectedBookIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await BookBatchActions.deleteFiles(
      ids: Array(selectedBookIds),
      instanceId: current.instanceId,
      using: batchController
    )
    finishBatchSelection(Set(outcome.failed))
  }

  private func finishBatchSelection(_ failedIds: Set<String>) {
    withAnimation {
      selectedBookIds = failedIds
      isSelectionMode = !failedIds.isEmpty
    }
    Task { await revalidateBooks() }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedBookIds.removeAll()
      isSelectionMode = false
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
