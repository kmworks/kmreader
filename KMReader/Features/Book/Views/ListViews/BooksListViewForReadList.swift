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

  @State private var bookViewModel = BookViewModel()
  @State private var selectedBookIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var isDeleting = false
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

        if supportsSelectionMode && !isSelectionMode && current.isAdmin {
          Button {
            withAnimation {
              isSelectionMode = true
            }
          } label: {
            Image(systemName: "checkmark.circle")
          }
          .adaptiveButtonStyle(.bordered)
          .optimizedControlSize()
          .transition(.opacity.combined(with: .scale))
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

      if readListItem != nil {
        ReadListBooksQueryView(
          readListId: readListId,
          readListContext: readListContext,
          bookViewModel: bookViewModel,
          browseOpts: browseOpts,
          browseLayout: layoutMode,
          isSelectionMode: isSelectionMode,
          selectedBookIds: $selectedBookIds,
          isAdmin: current.isAdmin
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
