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

  @State private var browseOpts: SeriesBrowseOptions = SeriesBrowseOptions()
  @State private var viewModel = SeriesViewModel()
  @State private var initializedKey: String?
  @State private var selectedSeriesIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var isSubmitting = false
  @State private var showCollectionPicker = false

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
          isSubmitting: isSubmitting,
          addLabel: String(localized: "Add to Collection"),
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
        isSelectionMode: supportsSelectionMode && isSelectionMode,
        selectedSeriesIds: $selectedSeriesIds
      )
    }
    .task(id: initializationKey) {
      guard initializedKey != initializationKey else { return }

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
      Task {
        await loadSeries(refresh: true)
      }
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesIds: Array(selectedSeriesIds),
        onSelect: { collectionId in
          addSelectedToCollection(collectionId: collectionId)
        }
      )
    }
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
    guard !selectedSeriesIds.isEmpty, !isSubmitting else { return }

    isSubmitting = true
    defer { isSubmitting = false }

    let seriesIds = Array(selectedSeriesIds)
    let outcome = await withTaskGroup(
      of: (id: String, error: Error?).self,
      returning: (succeeded: [String], firstError: Error?).self
    ) { group in
      for seriesId in seriesIds {
        group.addTask {
          do {
            if read {
              try await SeriesService.markAsRead(seriesId: seriesId)
            } else {
              try await SeriesService.markAsUnread(seriesId: seriesId)
            }
            return (seriesId, nil)
          } catch {
            return (seriesId, error)
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
      await withTaskGroup(of: Void.self) { group in
        for seriesId in outcome.succeeded {
          group.addTask {
            _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
            try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
            await ContentProjectionNotifier.postSeriesBooksDidChange(
              seriesId: seriesId,
              reason: .readingProgress
            )
          }
        }
      }
      await DashboardSectionRefreshNotifier.postReadStatusChanged(
        source: .manual,
        reason: "Series read status changed"
      )
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alert(error: firstError)
    } else if read {
      ErrorManager.shared.notify(message: String(localized: "notification.series.markedRead"))
    } else {
      ErrorManager.shared.notify(message: String(localized: "notification.series.markedUnread"))
    }

    withAnimation {
      selectedSeriesIds.removeAll()
      isSelectionMode = false
    }

    await loadSeries(refresh: true)
  }

  private func addSelectedToCollection(collectionId: String) {
    let seriesIds = Array(selectedSeriesIds)
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
        withAnimation {
          selectedSeriesIds.removeAll()
          isSelectionMode = false
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
