//
// BooksListViewForSeries.swift
//
//

import SwiftUI

// Books list view for series detail
struct BooksListViewForSeries: View {
  let seriesId: String
  @Bindable var bookViewModel: BookViewModel
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  @AppStorage("seriesDetailLayout") private var layoutMode: BrowseLayoutMode = .list
  @AppStorage("seriesBookBrowseOptions") private var browseOpts: BookBrowseOptions =
    BookBrowseOptions()
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var selectedBookIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var isSubmitting = false
  @State private var showReadListPicker = false
  @State private var allSeriesBookIds: [String] = []
  @State private var loadedSeriesId: String?

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
        BookFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: $showSavedFilters,
          filterType: .seriesBooks,
          seriesId: seriesId,
          layoutMode: $layoutMode
        )

        if supportsSelectionMode && !isSelectionMode && !isOffline {
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
        SelectionActionsToolbar(
          selectedCount: selectedBookIds.count,
          totalCount: allSeriesBookIds.count,
          isSubmitting: isSubmitting,
          addLabel: String(localized: "Add to Read List"),
          onSelectAll: {
            if selectedBookIds.count == allSeriesBookIds.count {
              selectedBookIds.removeAll()
            } else {
              selectedBookIds = Set(allSeriesBookIds)
            }
          },
          onMarkRead: {
            Task {
              await markSelected(read: true)
            }
          },
          onMarkUnread: {
            Task {
              await markSelected(read: false)
            }
          },
          onAdd: {
            showReadListPicker = true
          },
          onCancel: {
            isSelectionMode = false
            selectedBookIds.removeAll()
          }
        )
        .padding(.horizontal)
      }

      SeriesBooksQueryView(
        seriesId: seriesId,
        bookViewModel: bookViewModel,
        browseOpts: browseOpts,
        browseLayout: layoutMode,
        isSelectionMode: supportsSelectionMode && isSelectionMode,
        selectedBookIds: $selectedBookIds
      )
    }
    .task(id: seriesId) {
      guard loadedSeriesId != seriesId else { return }
      loadedSeriesId = seriesId
      await refreshBooks(refresh: true)
    }
    .onChange(of: browseOpts) {
      Task {
        await refreshBooks(refresh: true)
      }
    }
    .onChange(of: isSelectionMode) {
      if isSelectionMode {
        Task {
          await loadAllSeriesBookIds()
        }
      }
    }
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookIds: selectedBookIdsInSeriesOrder,
        onSelect: { readListId in
          addSelectedToReadList(readListId: readListId)
        },
        onCreate: { _ in
          exitSelectionMode()
        }
      )
    }
  }

  /// Selected ids in series order, so read-list appends keep that order.
  private var selectedBookIdsInSeriesOrder: [String] {
    allSeriesBookIds.filter(selectedBookIds.contains)
  }

  private func loadAllSeriesBookIds() async {
    guard let database = try? await DatabaseOperator.database() else { return }
    allSeriesBookIds = await database.fetchAllSeriesBookIds(
      seriesId: seriesId,
      instanceId: current.instanceId
    )
  }

  private func refreshBooks(refresh: Bool) async {
    await bookViewModel.loadSeriesBooks(
      seriesId: seriesId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }

  private func addSelectedToReadList(readListId: String) {
    let bookIds = selectedBookIdsInSeriesOrder
    guard !bookIds.isEmpty else { return }

    Task {
      do {
        try await ReadListService.addBooksToReadList(
          readListId: readListId,
          bookIds: bookIds
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        await ContentProjectionNotifier.postReadListDidChange(readListId: readListId)
        exitSelectionMode()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedBookIds.removeAll()
      isSelectionMode = false
    }
  }

  private func markSelected(read: Bool) async {
    guard !selectedBookIds.isEmpty, !isSubmitting else { return }

    isSubmitting = true
    defer { isSubmitting = false }

    let bookIds = Array(selectedBookIds)
    let outcome = await withTaskGroup(
      of: (id: String, error: Error?).self,
      returning: (succeeded: [String], failed: [String], firstError: Error?).self
    ) { group in
      for bookId in bookIds {
        group.addTask {
          do {
            if read {
              try await BookService.markAsRead(bookId: bookId)
            } else {
              try await BookService.markAsUnread(bookId: bookId)
            }
            return (bookId, nil)
          } catch {
            return (bookId, error)
          }
        }
      }
      var succeeded: [String] = []
      var failed: [String] = []
      var firstError: Error?
      for await result in group {
        if let error = result.error {
          failed.append(result.id)
          if firstError == nil { firstError = error }
        } else {
          succeeded.append(result.id)
        }
      }
      return (succeeded: succeeded, failed: failed, firstError: firstError)
    }

    // Sync whatever succeeded so the UI never goes stale, then report failures.
    if !outcome.succeeded.isEmpty {
      _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
      try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
      await ContentProjectionNotifier.postSeriesBooksDidChange(
        seriesId: seriesId,
        reason: .readingProgress
      )
      await DashboardSectionRefreshNotifier.postReadStatusChanged(
        source: .manual,
        reason: "Books read status changed"
      )
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alert(error: firstError)
    } else if read {
      ErrorManager.shared.notify(message: String(localized: "notification.book.markedRead"))
    } else {
      ErrorManager.shared.notify(message: String(localized: "notification.book.markedUnread"))
    }

    // Keep the failed items selected so the batch can be retried.
    withAnimation {
      if outcome.failed.isEmpty {
        selectedBookIds.removeAll()
        isSelectionMode = false
      } else {
        selectedBookIds = Set(outcome.failed)
      }
    }

    await refreshBooks(refresh: true)
  }
}
