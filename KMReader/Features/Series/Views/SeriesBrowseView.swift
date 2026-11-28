//
// SeriesBrowseView.swift
//
//

import SwiftUI

struct SeriesBrowseView: View {
  let libraryIds: [String]
  let searchText: String
  let refreshTrigger: UUID
  let metadataFilter: MetadataFilterConfig?
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  @AppStorage("seriesBrowseOptions") private var storedBrowseOpts: SeriesBrowseOptions = SeriesBrowseOptions()
  @AppStorage("seriesBrowseLayout") private var browseLayout: BrowseLayoutMode = .grid
  @AppStorage("searchIgnoreFilters") private var searchIgnoreFilters: Bool = false
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var browseOpts: SeriesBrowseOptions = SeriesBrowseOptions()
  @State private var viewModel = SeriesViewModel()
  @State private var initializedKey: String?
  @State private var selectedSeriesIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showCollectionPicker = false
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
  private var loadedSeriesIds: [String] {
    viewModel.pagination.items.map(\.id)
  }

  var body: some View {
    VStack {
      HStack(spacing: 8) {
        SeriesFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: $showSavedFilters,
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
          selectedCount: selectedSeriesIds.count,
          totalCount: loadedSeriesIds.count,
          isSubmitting: batchController.isRunning,
          completedCount: batchController.completedCount,
          runningTotalCount: batchController.totalCount,
          addLabel: String(localized: "Add to Collection"),
          editLabel: String(localized: "Edit Metadata"),
          deleteLabel: current.isAdmin ? String(localized: "Delete Files") : nil,
          komfMatchLabel: KomfIntegrationStore.shared.isAvailable
            ? String(localized: "Match with komf") : nil,
          onSelectAll: {
            if selectedSeriesIds.count == loadedSeriesIds.count {
              selectedSeriesIds.removeAll()
            } else {
              selectedSeriesIds = Set(loadedSeriesIds)
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
            showCollectionPicker = true
          },
          onEdit: {
            showBatchEditor = true
          },
          onDelete: {
            showDeleteConfirmation = true
          },
          onKomfMatch: {
            Task { await matchSelectedWithKomf() }
          },
          onCancel: {
            isSelectionMode = false
            selectedSeriesIds.removeAll()
          }
        )
        .padding(.horizontal)
      }

      SeriesQueryView(
        libraryIds: libraryIds,
        searchText: searchText,
        browseOpts: effectiveBrowseOpts,
        browseLayout: browseLayout,
        viewModel: viewModel,
        selectedSeriesIds: supportsSelectionMode && isSelectionMode ? $selectedSeriesIds : nil
      )
    }
    .task(id: initializationKey) {
      guard initializedKey != initializationKey else { return }

      // Replaced scopes must not keep acting on items hidden by the new query.
      selectedSeriesIds.removeAll()
      if let metadataFilter = metadataFilter {
        var opts = SeriesBrowseOptions()
        opts.metadataFilter = metadataFilter
        browseOpts = opts
      } else {
        browseOpts = storedBrowseOpts
      }
      initializedKey = initializationKey
      await loadSeries(refresh: true)
    }
    .onChange(of: refreshTrigger) { _, _ in
      selectedSeriesIds.removeAll()
      Task {
        await loadSeries(refresh: true)
      }
    }
    .onChange(of: browseOpts) { oldValue, newValue in
      if oldValue != newValue {
        if metadataFilter == nil {
          storedBrowseOpts = newValue
        }
        Task {
          await loadSeries(refresh: true)
        }
      }
    }
    .onChange(of: storedBrowseOpts) { _, newValue in
      if browseOpts != newValue {
        browseOpts = newValue
      }
    }
    .onChange(of: searchText) { _, newValue in
      selectedSeriesIds.removeAll()
      Task {
        await loadSeries(refresh: true)
      }
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesIds: selectedSeriesIdsInDisplayOrder,
        onSelect: { collectionId in
          addSelectedToCollection(collectionId: collectionId)
        },
        onCreate: { _ in
          exitSelectionMode()
        }
      )
    }
    .sheet(isPresented: $showBatchEditor) {
      SeriesBatchEditSheet(
        seriesIds: selectedSeriesIdsInDisplayOrder,
        onCompleted: finishBatchSelection
      )
    }
    .alert("Delete Series Files", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task { await deleteSelectedFiles() }
      }
    } message: {
      Text("batch.series.deleteConfirmation \(selectedSeriesIds.count)")
    }
  }

  /// Selected ids in display order, so collection appends keep that order.
  private var selectedSeriesIdsInDisplayOrder: [String] {
    loadedSeriesIds.filter(selectedSeriesIds.contains)
  }

  private var effectiveBrowseOpts: SeriesBrowseOptions {
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

  private func loadSeries(refresh: Bool) async {
    await viewModel.loadSeries(
      browseOpts: effectiveBrowseOpts,
      searchText: searchText,
      libraryIds: libraryIds,
      refresh: refresh
    )
  }

  private func markSelected(read: Bool) async {
    guard !selectedSeriesIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await SeriesBatchActions.mark(
      ids: Array(selectedSeriesIds),
      read: read,
      using: batchController
    )

    withAnimation {
      selectedSeriesIds = Set(outcome.failed)
      isSelectionMode = !outcome.failed.isEmpty
    }
    await loadSeries(refresh: true)
  }

  private func addSelectedToCollection(collectionId: String) {
    let seriesIds = selectedSeriesIdsInDisplayOrder
    guard !seriesIds.isEmpty else { return }

    Task {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: collectionId,
          seriesIds: seriesIds
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        await ContentProjectionNotifier.postCollectionDidChange(collectionId: collectionId)
        exitSelectionMode()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deleteSelectedFiles() async {
    guard !selectedSeriesIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await SeriesBatchActions.deleteFiles(
      ids: Array(selectedSeriesIds),
      instanceId: current.instanceId,
      using: batchController
    )
    finishBatchSelection(Set(outcome.failed))
  }

  private func matchSelectedWithKomf() async {
    guard !selectedSeriesIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await SeriesBatchActions.matchWithKomf(
      ids: Array(selectedSeriesIds),
      using: batchController
    )
    finishBatchSelection(Set(outcome.failed))
  }

  private func finishBatchSelection(_ failedIds: Set<String>) {
    withAnimation {
      selectedSeriesIds = failedIds
      isSelectionMode = !failedIds.isEmpty
    }
    Task { await loadSeries(refresh: true) }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedSeriesIds.removeAll()
      isSelectionMode = false
    }
  }
}
