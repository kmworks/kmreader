//
// SmartListSeriesListView.swift
//
//

import SwiftUI

struct SmartListSeriesListView: View {
  let smartListId: String

  @AppStorage("smartListSeriesBrowseLayout") private var layoutMode: BrowseLayoutMode = .list
  @AppStorage("smartListSeriesBrowseOptions") private var browseOpts: SeriesBrowseOptions =
    SeriesBrowseOptions()
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var seriesViewModel = SeriesViewModel()
  @State private var showFilterSheet = false
  @State private var loadedSmartListId: String?
  @State private var selectedSeriesIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showCollectionPicker = false
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

  private var loadedSeriesIds: [String] {
    seriesViewModel.pagination.items.map(\.id)
  }

  private var selectedSeriesIdsInDisplayOrder: [String] {
    loadedSeriesIds.filter(selectedSeriesIds.contains)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        SeriesFilterView(
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
          onSelectAll: toggleSelectAll,
          onMarkRead: {
            Task { await markSelected(read: true) }
          },
          onMarkUnread: {
            Task { await markSelected(read: false) }
          },
          onAdd: { showCollectionPicker = true },
          onEdit: { showBatchEditor = true },
          onDelete: { showDeleteConfirmation = true },
          onKomfMatch: {
            Task { await matchSelectedWithKomf() }
          },
          onCancel: exitSelectionMode
        )
        .padding(.horizontal)
      }

      BrowseStateView(
        isLoading: seriesViewModel.isLoading,
        isEmpty: seriesViewModel.pagination.isEmpty,
        emptyIcon: ContentIcon.series,
        emptyTitle: LocalizedStringKey("No series found"),
        emptyMessage: LocalizedStringKey("Try adjusting the filters."),
        onRetry: {
          Task { await loadSeries(refresh: true) }
        }
      ) {
        switch layoutMode {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(seriesViewModel.pagination.items) { series in
              Group {
                if isSelectionMode {
                  SeriesSelectionItemView(
                    seriesId: series.id,
                    layout: layoutMode,
                    selectedSeriesIds: $selectedSeriesIds,
                    cardWidth: layoutMode.cardWidth
                  )
                } else {
                  SeriesQueryItemView(
                    seriesId: series.id,
                    layout: layoutMode,
                    cardWidth: layoutMode.cardWidth,
                    onItemMissing: {
                      seriesViewModel.removeSeries(id: series.id)
                    }
                  )
                }
              }
              .onAppear {
                if seriesViewModel.pagination.shouldLoadMore(after: series) {
                  Task { await loadSeries(refresh: false) }
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(seriesViewModel.pagination.items) { series in
              Group {
                if isSelectionMode {
                  SeriesSelectionItemView(
                    seriesId: series.id,
                    layout: .list,
                    selectedSeriesIds: $selectedSeriesIds
                  )
                } else {
                  SeriesQueryItemView(
                    seriesId: series.id,
                    layout: .list,
                    onItemMissing: {
                      seriesViewModel.removeSeries(id: series.id)
                    }
                  )
                }
              }
              .onAppear {
                if seriesViewModel.pagination.shouldLoadMore(after: series) {
                  Task { await loadSeries(refresh: false) }
                }
              }
              if !seriesViewModel.pagination.isLast(series) {
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
      await loadSeries(refresh: true)
    }
    .onChange(of: browseOpts) {
      Task {
        await loadSeries(refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .seriesProjectionDidChange)) { _ in
      Task { await revalidateSeries() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListMembershipDidChange)) { _ in
      Task { await revalidateSeries() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListsDidChange)) { notification in
      guard notification.userInfo?["smartListId"] as? String == smartListId else { return }
      Task { await revalidateSeries() }
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesIds: selectedSeriesIdsInDisplayOrder,
        onSelect: addSelectedToCollection,
        onCreate: { _ in finishBatchSelection([]) }
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

  private func toggleSelectAll() {
    if selectedSeriesIds.count == loadedSeriesIds.count {
      selectedSeriesIds.removeAll()
    } else {
      selectedSeriesIds = Set(loadedSeriesIds)
    }
  }

  private func markSelected(read: Bool) async {
    guard !selectedSeriesIds.isEmpty, !batchController.isRunning else { return }

    let outcome = await SeriesBatchActions.mark(
      ids: Array(selectedSeriesIds),
      read: read,
      using: batchController
    )
    finishBatchSelection(Set(outcome.failed))
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
        finishBatchSelection([])
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
    Task { await revalidateSeries() }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedSeriesIds.removeAll()
      isSelectionMode = false
    }
  }

  private func loadSeries(refresh: Bool) async {
    await seriesViewModel.loadSmartListSeries(
      smartListId: smartListId,
      browseOpts: browseOpts,
      refresh: refresh
    )
  }

  /// The stored server-side filter may be read-status-based even when the
  /// overlay options are not, so every series change revalidates the window.
  private func revalidateSeries() async {
    await seriesViewModel.revalidateSmartListSeries(
      smartListId: smartListId,
      browseOpts: browseOpts
    )
  }
}
