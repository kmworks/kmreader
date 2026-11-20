//
// CollectionSeriesListView.swift
//
//

import SwiftUI

// Series list view for collection
struct CollectionSeriesListView: View {
  let collectionId: String
  @Binding var showFilterSheet: Bool
  @Binding var showSavedFilters: Bool

  @AppStorage("collectionDetailLayout") private var layoutMode: BrowseLayoutMode = .list
  @AppStorage("collectionSeriesBrowseOptions") private var browseOpts: CollectionSeriesBrowseOptions =
    CollectionSeriesBrowseOptions()
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var seriesViewModel = SeriesViewModel()
  @State private var selectedSeriesIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var isDeleting = false
  @State private var isBatchSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showCollectionPicker = false
  @State private var showBatchEditor = false
  @State private var showDeleteConfirmation = false
  @State private var collectionItem: CollectionDisplayItem?
  @State private var loadedCollectionId: String?

  init(
    collectionId: String,
    showFilterSheet: Binding<Bool>,
    showSavedFilters: Binding<Bool>
  ) {
    self.collectionId = collectionId
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
        CollectionSeriesFilterView(
          browseOpts: $browseOpts,
          showFilterSheet: $showFilterSheet,
          showSavedFilters: $showSavedFilters,
          collectionId: collectionId,
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
          selectedCount: selectedSeriesIds.count,
          totalCount: collectionItem?.seriesCount ?? 0,
          isDeleting: isDeleting,
          onSelectAll: {
            if let seriesIds = collectionItem?.seriesIds {
              if selectedSeriesIds.count == seriesIds.count {
                selectedSeriesIds.removeAll()
              } else {
                selectedSeriesIds = Set(seriesIds)
              }
            }
          },
          onDelete: {
            Task {
              await deleteSelectedSeries()
            }
          },
          onCancel: {
            isSelectionMode = false
            selectedSeriesIds.removeAll()
          }
        )
        .padding(.horizontal)
      }

      if supportsSelectionMode && isBatchSelectionMode {
        SelectionActionsToolbar(
          selectedCount: selectedSeriesIds.count,
          totalCount: collectionItem?.seriesIds.count ?? 0,
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
          onCancel: exitBatchSelectionMode
        )
        .padding(.horizontal)
      }

      if collectionItem != nil {
        CollectionSeriesQueryView(
          collectionId: collectionId,
          seriesViewModel: seriesViewModel,
          browseOpts: browseOpts,
          browseLayout: layoutMode,
          isSelectionMode: isSelectionMode || isBatchSelectionMode,
          selectedSeriesIds: $selectedSeriesIds
        )
      } else if seriesViewModel.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      }
    }
    .task(id: collectionId) {
      guard loadedCollectionId != collectionId else { return }
      loadedCollectionId = collectionId
      await refreshSeries()
    }
    .onChange(of: browseOpts) {
      Task {
        await refreshSeries()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .seriesProjectionDidChange)) {
      notification in
      guard shouldRefreshForSeriesProjection(notification) else { return }
      Task { await revalidateSeriesIfNeeded(for: notification) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .collectionProjectionDidChange)) {
      notification in
      guard notification.userInfo?["collectionId"] as? String == collectionId else { return }
      Task { await revalidateSeries() }
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesIds: selectedSeriesIdsInCollectionOrder,
        onSelect: addSelectedToCollection,
        onCreate: { _ in finishBatchSelection([]) }
      )
    }
    .sheet(isPresented: $showBatchEditor) {
      SeriesBatchEditSheet(
        seriesIds: selectedSeriesIdsInCollectionOrder,
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

  private var selectedSeriesIdsInCollectionOrder: [String] {
    (collectionItem?.seriesIds ?? []).filter(selectedSeriesIds.contains)
  }

  private func toggleSelectAll() {
    guard let seriesIds = collectionItem?.seriesIds else { return }
    if selectedSeriesIds.count == seriesIds.count {
      selectedSeriesIds.removeAll()
    } else {
      selectedSeriesIds = Set(seriesIds)
    }
  }

  private func refreshSeries() async {
    await loadCollection()
    guard collectionItem != nil else { return }
    await seriesViewModel.loadCollectionSeries(
      collectionId: collectionId,
      browseOpts: browseOpts,
      refresh: true
    )
  }

  private func loadCollection() async {
    guard let database = try? await DatabaseOperator.database() else {
      collectionItem = nil
      return
    }
    collectionItem = try? await database.fetchCollectionDisplayItem(
      collectionId: collectionId,
      instanceId: current.instanceId
    )
  }

  /// Pure reading-progress changes (e.g. reader closed) are applied by the
  /// item rows themselves from GRDB; the ID list is only revalidated when the
  /// change can alter membership for the current browse options.
  private func revalidateSeriesIfNeeded(for notification: Notification) async {
    let reasons = ContentProjectionNotifier.changeReasons(from: notification)
    if reasons.isSubset(of: [.readingProgress]) && !browseOpts.isSensitiveToReadingProgress {
      await loadCollection()
      return
    }
    await revalidateSeries()
  }

  /// Projection-change-driven refresh: revalidates the loaded window in place
  /// so the scroll position and loaded pages are preserved.
  private func revalidateSeries() async {
    await loadCollection()
    guard collectionItem != nil else { return }
    await seriesViewModel.revalidateCollectionSeries(
      collectionId: collectionId,
      browseOpts: browseOpts
    )
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

  private func addSelectedToCollection(collectionId targetCollectionId: String) {
    let seriesIds = selectedSeriesIdsInCollectionOrder
    guard !seriesIds.isEmpty else { return }

    Task {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: targetCollectionId,
          seriesIds: seriesIds
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        await ContentProjectionNotifier.postCollectionDidChange(collectionId: targetCollectionId)
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
      isBatchSelectionMode = !failedIds.isEmpty
    }
    Task { await refreshSeries() }
  }

  private func exitBatchSelectionMode() {
    withAnimation {
      selectedSeriesIds.removeAll()
      isBatchSelectionMode = false
    }
  }

  private func deleteSelectedSeries() async {
    guard !selectedSeriesIds.isEmpty else { return }
    guard !isDeleting else { return }

    isDeleting = true
    defer { isDeleting = false }

    do {
      try await CollectionService.removeSeriesFromCollection(
        collectionId: collectionId,
        seriesIds: Array(selectedSeriesIds)
      )
      // Sync the collection to update its local series IDs
      _ = try? await SyncService.syncCollection(id: collectionId)
      await loadCollection()

      ErrorManager.shared.notify(
        message: String(localized: "notification.series.removedFromCollection"))

      // Clear selection and exit selection mode with animation
      withAnimation {
        selectedSeriesIds.removeAll()
        isSelectionMode = false
      }

      // Refresh the series list
      await refreshSeries()
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func shouldRefreshForSeriesProjection(_ notification: Notification) -> Bool {
    let changedIds = changedSeriesIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    guard let currentIds = collectionItem?.seriesIds else { return true }
    return !changedIds.isDisjoint(with: currentIds)
  }

  private func changedSeriesIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["seriesIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["seriesIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["seriesId"] as? String {
      return [id]
    }
    return []
  }

}
