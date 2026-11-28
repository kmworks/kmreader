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
  @State private var batchController = BatchOperationController()
  @State private var showReadListPicker = false
  @State private var showBatchEditor = false
  @State private var showDeleteConfirmation = false

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
          isSubmitting: batchController.isRunning,
          completedCount: batchController.completedCount,
          runningTotalCount: batchController.totalCount,
          addLabel: String(localized: "Add to Read List"),
          editLabel: String(localized: "Edit Metadata"),
          deleteLabel: current.isAdmin ? String(localized: "Delete Files") : nil,
          komfMatchLabel: nil,
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
          onEdit: {
            showBatchEditor = true
          },
          onDelete: {
            showDeleteConfirmation = true
          },
          onKomfMatch: {},
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
        selectedBookIds: supportsSelectionMode && isSelectionMode ? $selectedBookIds : nil
      )
      .task(id: initializationKey) {
        guard initializedKey != initializationKey else { return }

        // Replaced scopes must not keep acting on items hidden by the new query.
        selectedBookIds.removeAll()
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
        selectedBookIds.removeAll()
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
        selectedBookIds.removeAll()
        Task {
          await loadBooks(refresh: true)
        }
      }
    }
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookIds: selectedBookIdsInDisplayOrder,
        onSelect: { readListId in
          addSelectedToReadList(readListId: readListId)
        },
        onCreate: { _ in
          exitSelectionMode()
        }
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

  /// Selected ids in display order, so read-list appends keep the list's order.
  private var selectedBookIdsInDisplayOrder: [String] {
    loadedBookIds.filter(selectedBookIds.contains)
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
    guard !selectedBookIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await BookBatchActions.mark(
      ids: Array(selectedBookIds),
      read: read,
      instanceId: current.instanceId,
      using: batchController
    )

    withAnimation {
      selectedBookIds = Set(outcome.failed)
      isSelectionMode = !outcome.failed.isEmpty
    }
    await loadBooks(refresh: true)
  }

  private func addSelectedToReadList(readListId: String) {
    let bookIds = selectedBookIdsInDisplayOrder
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
    Task { await loadBooks(refresh: true) }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedBookIds.removeAll()
      isSelectionMode = false
    }
  }

}
