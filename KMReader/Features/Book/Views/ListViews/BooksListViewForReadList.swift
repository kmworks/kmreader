//
// BooksListViewForReadList.swift
//
//

import SwiftUI

// Books list view for read list
struct BooksListViewForReadList: View {
  let readListId: String
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  @AppStorage("readListDetailLayout") private var layoutMode: BrowseLayoutMode = .list
  @AppStorage("readListBookBrowseOptions") private var browseOpts: ReadListBookBrowseOptions =
    ReadListBookBrowseOptions()
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var bookViewModel = BookViewModel()
  @State private var selectedBookIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var isDeleting = false
  @State private var isBatchSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showAddToReadListPicker = false
  @State private var showBatchEditor = false
  @State private var showDeleteConfirmation = false
  @State private var readListItem: ReadListDisplayItem?
  @State private var loadedReadListId: String?

  private var readListContext: ReaderReadListContext? {
    guard let readListItem else { return nil }
    return ReaderReadListContext(id: readListItem.readListId, name: readListItem.name)
  }

  init(
    readListId: String,
    showFilterSheet: Binding<Bool>,
    showSavedFilters: Binding<Bool>
  ) {
    self.readListId = readListId
    self._showFilterSheet = showFilterSheet
    self._showSavedFilters = showSavedFilters
  }

  private var supportsSelectionMode: Bool {
    #if os(tvOS)
      return false
    #else
      return true
    #endif
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ReadListBookFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: $showSavedFilters,
          readListId: readListId,
          layoutMode: $layoutMode
        )

        if supportsSelectionMode && !isSelectionMode && !isBatchSelectionMode {
          if !isOffline {
            Button {
              withAnimation {
                isBatchSelectionMode = true
              }
            } label: {
              Image(systemName: "checkmark.circle")
            }
            .adaptiveButtonStyle(.bordered)
            .optimizedControlSize()
            .transition(.opacity.combined(with: .scale))
          }

          if current.isAdmin {
            Button {
              withAnimation {
                isSelectionMode = true
              }
            } label: {
              Image(systemName: "minus.circle")
            }
            .adaptiveButtonStyle(.bordered)
            .optimizedControlSize()
            .accessibilityLabel(String(localized: "Edit Members"))
            .transition(.opacity.combined(with: .scale))
          }
        }
      }
      .padding(.horizontal)

      if supportsSelectionMode && isSelectionMode {
        SelectionToolbar(
          selectedCount: selectedBookIds.count,
          totalCount: readListItem?.bookCount ?? 0,
          isDeleting: isDeleting,
          onSelectAll: {
            if let bookIds = readListItem?.bookIds {
              if selectedBookIds.count == bookIds.count {
                selectedBookIds.removeAll()
              } else {
                selectedBookIds = Set(bookIds)
              }
            }
          },
          onDelete: {
            Task {
              await deleteSelectedBooks()
            }
          },
          onCancel: {
            isSelectionMode = false
            selectedBookIds.removeAll()
          }
        )
        .padding(.horizontal)
      }

      if supportsSelectionMode && isBatchSelectionMode {
        SelectionActionsToolbar(
          selectedCount: selectedBookIds.count,
          totalCount: readListItem?.bookIds.count ?? 0,
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
          onAdd: {
            showAddToReadListPicker = true
          },
          onEdit: {
            showBatchEditor = true
          },
          onDelete: {
            showDeleteConfirmation = true
          },
          onKomfMatch: {},
          onCancel: exitBatchSelectionMode
        )
        .padding(.horizontal)
      }

      if readListItem != nil {
        ReadListBooksQueryView(
          readListId: readListId,
          readListContext: readListContext,
          bookViewModel: bookViewModel,
          browseOpts: browseOpts,
          browseLayout: layoutMode,
          isSelectionMode: isSelectionMode || isBatchSelectionMode,
          selectedBookIds: $selectedBookIds
        )
      } else if bookViewModel.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      }
    }
    .task(id: readListId) {
      guard loadedReadListId != readListId else { return }
      loadedReadListId = readListId
      await refreshBooks()
    }
    .onChange(of: browseOpts) {
      Task {
        await refreshBooks()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) {
      notification in
      guard shouldRefreshForBookProjection(notification) else { return }
      Task { await revalidateBooksIfNeeded(for: notification) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .readListProjectionDidChange)) {
      notification in
      guard notification.userInfo?["readListId"] as? String == readListId else { return }
      Task { await revalidateBooks() }
    }
    .sheet(isPresented: $showAddToReadListPicker) {
      ReadListPickerSheet(
        bookIds: selectedBookIdsInReadListOrder,
        onSelect: addSelectedToReadList,
        onCreate: { _ in finishBatchSelection([]) }
      )
    }
    .sheet(isPresented: $showBatchEditor) {
      BookBatchEditSheet(
        bookIds: selectedBookIdsInReadListOrder,
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

  private var selectedBookIdsInReadListOrder: [String] {
    (readListItem?.bookIds ?? []).filter(selectedBookIds.contains)
  }

  private func toggleSelectAll() {
    guard let bookIds = readListItem?.bookIds else { return }
    if selectedBookIds.count == bookIds.count {
      selectedBookIds.removeAll()
    } else {
      selectedBookIds = Set(bookIds)
    }
  }

  private func refreshBooks() async {
    await loadReadList()
    guard readListItem != nil else { return }
    await bookViewModel.loadReadListBooks(
      readListId: readListId,
      browseOpts: browseOpts,
      refresh: true
    )
  }

  private func loadReadList() async {
    guard let database = try? await DatabaseOperator.database() else {
      readListItem = nil
      return
    }
    readListItem = try? await database.fetchReadListDisplayItem(
      readListId: readListId,
      instanceId: current.instanceId
    )
  }

  /// Pure reading-progress changes (e.g. reader closed) are applied by the
  /// item rows themselves from GRDB; the ID list is only revalidated when the
  /// change can alter membership for the current browse options.
  private func revalidateBooksIfNeeded(for notification: Notification) async {
    let reasons = ContentProjectionNotifier.changeReasons(from: notification)
    if reasons.isSubset(of: [.readingProgress]) && !browseOpts.isSensitiveToReadingProgress {
      await loadReadList()
      return
    }
    await revalidateBooks()
  }

  /// Projection-change-driven refresh: revalidates the loaded window in place
  /// so the scroll position and loaded pages are preserved.
  private func revalidateBooks() async {
    await loadReadList()
    guard readListItem != nil else { return }
    await bookViewModel.revalidateReadListBooks(
      readListId: readListId,
      browseOpts: browseOpts
    )
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

  private func addSelectedToReadList(readListId targetReadListId: String) {
    let bookIds = selectedBookIdsInReadListOrder
    guard !bookIds.isEmpty else { return }

    Task {
      do {
        try await ReadListService.addBooksToReadList(
          readListId: targetReadListId,
          bookIds: bookIds
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        await ContentProjectionNotifier.postReadListDidChange(readListId: targetReadListId)
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
      isBatchSelectionMode = !failedIds.isEmpty
    }
    Task { await refreshBooks() }
  }

  private func exitBatchSelectionMode() {
    withAnimation {
      selectedBookIds.removeAll()
      isBatchSelectionMode = false
    }
  }

  private func deleteSelectedBooks() async {
    guard !selectedBookIds.isEmpty else { return }
    guard !isDeleting else { return }

    isDeleting = true
    defer { isDeleting = false }

    do {
      try await ReadListService.removeBooksFromReadList(
        readListId: readListId,
        bookIds: Array(selectedBookIds)
      )
      await loadReadList()

      ErrorManager.shared.notify(message: String(localized: "notification.readList.booksRemoved"))

      // Clear selection and exit selection mode with animation
      withAnimation {
        selectedBookIds.removeAll()
        isSelectionMode = false
      }

      // Refresh the books list
      await refreshBooks()
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func shouldRefreshForBookProjection(_ notification: Notification) -> Bool {
    let changedIds = changedBookIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    guard let currentIds = readListItem?.bookIds else { return true }
    return !changedIds.isDisjoint(with: currentIds)
  }

  private func changedBookIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["bookIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["bookIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["bookId"] as? String {
      return [id]
    }
    return []
  }

}
