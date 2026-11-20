//
// MissingPostersView.swift
//
//

import SwiftUI

struct MissingPostersView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var hasLoaded = false
  @State private var pagination = PaginationState<Book>(pageSize: 20)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredItemId: String?
  @State private var selectedBookIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showReadListPicker = false
  @State private var showBatchEditor = false
  @State private var showDeleteConfirmation = false

  private var loadedBookIds: [String] {
    pagination.items.map(\.id)
  }

  private var selectedBookIdsInDisplayOrder: [String] {
    loadedBookIds.filter(selectedBookIds.contains)
  }

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            VStack(spacing: 8) {
              Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.green)
              Text(String(localized: "No missing posters"))
                .foregroundColor(.secondary)
            }
            Spacer()
          }
          .padding(.vertical)
        }
      } else {
        if isSelectionMode {
          Section {
            SelectionActionsToolbar(
              selectedCount: selectedBookIds.count,
              totalCount: loadedBookIds.count,
              isSubmitting: batchController.isRunning,
              completedCount: batchController.completedCount,
              runningTotalCount: batchController.totalCount,
              addLabel: String(localized: "Add to Read List"),
              editLabel: String(localized: "Edit Metadata"),
              deleteLabel: String(localized: "Delete Files"),
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
          }
        }

        Section {
          ForEach(pagination.items) { book in
            if isSelectionMode {
              BookSelectionItemView(
                bookId: book.id,
                layout: .list,
                selectedBookIds: $selectedBookIds,
                showSeriesTitle: true
              )
              .onAppear { loadMoreIfNeeded(after: book) }
            } else {
              missingPosterRow(book: book)
            }
          }

          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .padding(.vertical)
          }
        }
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(String(localized: "Missing Posters"))
    .task {
      if current.isAdmin && !hasLoaded {
        await loadData(refresh: true)
        hasLoaded = true
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadData(refresh: true)
      }
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        if current.isAdmin && !isSelectionMode && !pagination.isEmpty {
          ToolbarItem(placement: .automatic) {
            Button {
              withAnimation { isSelectionMode = true }
            } label: {
              Image(systemName: "checkmark.circle")
            }
          }
        }
      }
    #endif
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

  @ViewBuilder
  private func missingPosterRow(book: Book) -> some View {
    NavigationLink(value: NavDestination.bookDetail(bookId: book.id)) {
      HStack(spacing: 12) {
        ThumbnailImage(
          id: book.id,
          type: .book,
          shadowStyle: .none,
          width: 40,
          cornerRadius: 4,
          isTransitionSource: false
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(book.seriesTitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)

          Text(book.metadata.title)
            .lineLimit(2)

          HStack(spacing: 8) {
            if !book.media.mediaType.isEmpty {
              Text(book.media.mediaType)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if book.deleted {
              Text(String(localized: "Unavailable"))
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15), in: Capsule())
                .foregroundColor(.red)
            }
          }
        }
      }
    }
    .onAppear { loadMoreIfNeeded(after: book) }
  }

  private func loadMoreIfNeeded(after book: Book) {
    guard pagination.hasMorePages,
      !isLoadingMore,
      pagination.shouldLoadMore(after: book, threshold: 3),
      lastTriggeredItemId != book.id
    else { return }
    lastTriggeredItemId = book.id
    Task { await loadMore() }
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
    Task { await loadData(refresh: true) }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedBookIds.removeAll()
      isSelectionMode = false
    }
  }

  private func loadData(refresh: Bool) async {
    if refresh {
      withAnimation {
        pagination.reset()
      }
      lastTriggeredItemId = nil
    }

    withAnimation {
      isLoading = true
    }
    do {
      let page = try await MediaManagementService.getMissingPosterBooks(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredItemId = nil
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoading = false
    }
  }

  private func loadMore() async {
    guard pagination.hasMorePages && !isLoadingMore else { return }
    withAnimation {
      isLoadingMore = true
    }
    do {
      let page = try await MediaManagementService.getMissingPosterBooks(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredItemId = nil
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoadingMore = false
    }
  }
}
