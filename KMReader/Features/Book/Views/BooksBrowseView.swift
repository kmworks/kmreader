//
// BooksBrowseView.swift
//
//

import SwiftUI

struct BooksBrowseView: View {
  let libraryIds: [String]
  let searchText: String
  let refreshTrigger: UUID
  let metadataFilter: MetadataFilterConfig?
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  @AppStorage("bookBrowseOptions") private var storedBrowseOpts: BookBrowseOptions = BookBrowseOptions()
  @State private var browseOpts: BookBrowseOptions = BookBrowseOptions()
  @AppStorage("bookBrowseLayout") private var browseLayout: BrowseLayoutMode = .grid
  @AppStorage("searchIgnoreFilters") private var searchIgnoreFilters: Bool = false
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var viewModel = BookViewModel()
  @State private var initializedKey: String?
  @State private var selectedBookIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var isSubmitting = false
  @State private var showReadListPicker = false

  private var supportsSelectionMode: Bool {
    #if os(tvOS)
      return false
    #else
      return true
    #endif
  }

  /// kmweb parity: Select All covers the currently loaded page window.
  private var loadedBookIds: [String] {
    viewModel.pagination.items.map(\.id)
  }

  var body: some View {
    VStack {
      HStack(spacing: 8) {
        BookFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: $showSavedFilters,
          filterType: .books,
          libraryIds: libraryIds,
          usesRelevanceSort: usesRelevanceSort,
          ignoresFiltersForSearch: ignoresFiltersForSearch,
          layoutMode: $browseLayout
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
          totalCount: loadedBookIds.count,
          isSubmitting: isSubmitting,
          addLabel: String(localized: "Add to Read List"),
          onSelectAll: {
            if selectedBookIds.count == loadedBookIds.count {
              selectedBookIds.removeAll()
            } else {
              selectedBookIds = Set(loadedBookIds)
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

      BooksQueryView(
        libraryIds: libraryIds,
        searchText: searchText,
        browseOpts: effectiveBrowseOpts,
        browseLayout: browseLayout,
        viewModel: viewModel,
        isSelectionMode: supportsSelectionMode && isSelectionMode,
        selectedBookIds: $selectedBookIds
      )
      .task(id: initializationKey) {
        guard initializedKey != initializationKey else { return }

        if let metadataFilter = metadataFilter {
          var opts = BookBrowseOptions()
          opts.metadataFilter = metadataFilter
          browseOpts = opts
        } else {
          browseOpts = storedBrowseOpts
        }
        initializedKey = initializationKey
        await loadBooks(refresh: true)
      }
      .onChange(of: refreshTrigger) { _, _ in
        Task {
          await loadBooks(refresh: true)
        }
      }
      .onChange(of: browseOpts) { oldValue, newValue in
        if oldValue != newValue {
          if metadataFilter == nil {
            storedBrowseOpts = newValue
          }
          Task {
            await loadBooks(refresh: true)
          }
        }
      }
      .onChange(of: storedBrowseOpts) { _, newValue in
        if browseOpts != newValue {
          browseOpts = newValue
        }
      }
      .onChange(of: searchText) { _, newValue in
        Task {
          await loadBooks(refresh: true)
        }
      }
      .sheet(isPresented: $showReadListPicker) {
        ReadListPickerSheet(
          bookIds: Array(selectedBookIds),
          onSelect: { readListId in
            addSelectedToReadList(readListId: readListId)
          }
        )
      }
    }
  }

  private var effectiveBrowseOpts: BookBrowseOptions {
    ignoresFiltersForSearch ? browseOpts.filtersCleared : browseOpts
  }

  private var usesRelevanceSort: Bool {
    !isOffline && !searchText.isEmpty
  }

  private var ignoresFiltersForSearch: Bool {
    searchIgnoreFilters && !searchText.isEmpty
  }

  private var initializationKey: String {
    [
      libraryIds.joined(separator: ","),
      metadataFilter?.rawValue ?? "",
    ].joined(separator: "|")
  }

  private func loadBooks(refresh: Bool) async {
    await viewModel.loadBrowseBooks(
      browseOpts: effectiveBrowseOpts,
      searchText: searchText,
      libraryIds: libraryIds,
      refresh: refresh
    )
  }

  private func markSelected(read: Bool) async {
    guard !selectedBookIds.isEmpty, !isSubmitting else { return }

    isSubmitting = true
    defer { isSubmitting = false }

    let bookIds = Array(selectedBookIds)
    let outcome = await withTaskGroup(
      of: (id: String, error: Error?).self,
      returning: (succeeded: [String], firstError: Error?).self
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
      var firstError: Error?
      for await result in group {
        if let error = result.error {
          if firstError == nil { firstError = error }
        } else {
          succeeded.append(result.id)
        }
      }
      return (succeeded: succeeded, firstError: firstError)
    }

    // Sync whatever succeeded so the UI never goes stale, then report failures.
    if !outcome.succeeded.isEmpty {
      await SyncService.syncVisitedItems(
        bookIds: Set(outcome.succeeded),
        seriesIds: await seriesIds(forBookIds: outcome.succeeded)
      )
      await ContentProjectionNotifier.postBooksAndSeriesDidChange(
        bookIds: outcome.succeeded,
        instanceId: current.instanceId,
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

    withAnimation {
      selectedBookIds.removeAll()
      isSelectionMode = false
    }

    await loadBooks(refresh: true)
  }

  /// Series ids of the given books from the local mirror, for the batch re-sync.
  private func seriesIds(forBookIds bookIds: [String]) async -> Set<String> {
    guard let database = try? await DatabaseOperator.database() else { return [] }
    var ids: Set<String> = []
    for bookId in bookIds {
      if let item = try? await database.fetchBookDisplayItem(
        bookId: bookId,
        instanceId: current.instanceId
      ) {
        ids.insert(item.book.seriesId)
      }
    }
    return ids
  }

  private func addSelectedToReadList(readListId: String) {
    let bookIds = Array(selectedBookIds)
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
        withAnimation {
          selectedBookIds.removeAll()
          isSelectionMode = false
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

}
