//
// LibraryListContent.swift
//
//

import SwiftUI

struct LibraryListContent: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var isLoading = false
  @State private var isLoadingMetrics = false
  @State private var selectedLibraryIds: [String]
  @State private var libraries: [SidebarLibraryItem] = []
  @State private var allLibrariesEntry: SidebarLibraryItem?

  let selectionEnabled: Bool
  let loadMetrics: Bool
  let alwaysRefreshMetrics: Bool
  let forceMetricsOnAppear: Bool
  let enablePullToRefresh: Bool
  let onEditLibrary: ((String) -> Void)?
  let onDeleteLibrary: ((LibrarySelection) -> Void)?
  let refreshTrigger: Int

  private let metricsLoader = LibraryMetricsLoader.shared

  init(
    selectionEnabled: Bool = false,
    loadMetrics: Bool = true,
    alwaysRefreshMetrics: Bool = false,
    forceMetricsOnAppear: Bool = true,
    enablePullToRefresh: Bool = true,
    onEditLibrary: ((String) -> Void)? = nil,
    onDeleteLibrary: ((LibrarySelection) -> Void)? = nil,
    refreshTrigger: Int = 0
  ) {
    let initialSelection = AppConfig.dashboard.libraryIds
    self.selectionEnabled = selectionEnabled
    self.loadMetrics = loadMetrics
    self.alwaysRefreshMetrics = alwaysRefreshMetrics
    self.forceMetricsOnAppear = forceMetricsOnAppear
    self.enablePullToRefresh = enablePullToRefresh
    self.onEditLibrary = onEditLibrary
    self.onDeleteLibrary = onDeleteLibrary
    self.refreshTrigger = refreshTrigger
    _selectedLibraryIds = State(initialValue: initialSelection)
  }

  var body: some View {
    if enablePullToRefresh {
      listContent
        .refreshable {
          await refreshLibraries(forceMetrics: true)
        }
    } else {
      listContent
    }
  }

  private var listContent: some View {
    Form {
      if isLoading && libraries.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView(String(localized: "Loading Libraries…"))
            Spacer()
          }
        }
      } else if libraries.isEmpty {
        Section {
          ContentUnavailableView {
            Label(String(localized: "No libraries found"), systemImage: ContentIcon.library)
          } description: {
            Text(String(localized: "Add a library from Komga's web interface to manage it here."))
          } actions: {
            Button(String(localized: "Retry")) {
              Task {
                await refreshLibraries()
              }
            }
            .adaptiveButtonStyle(.borderedProminent)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        }
      } else {
        Section {
          allLibrariesRowView()
          ForEach(libraries, id: \.libraryId) { library in
            LibraryRowView(
              library: library,
              selectionEnabled: selectionEnabled,
              isSelected: selectedLibraryIds.contains(library.libraryId),
              onSelect: selectionEnabled ? { handleLibrarySelection(for: library.libraryId) } : nil,
              onAction: { action in
                action.perform(for: library.libraryId)
              },
              onEdit: onEditLibrary != nil ? { onEditLibrary?(library.libraryId) } : nil,
              onDelete: onDeleteLibrary != nil
                ? { onDeleteLibrary?(LibrarySelection(sidebarItem: library)) } : nil
            )
          }
        }
      }
    }
    .formStyle(.grouped)
    .task(id: current.instanceId) {
      await refreshLibraries(forceMetrics: forceMetricsOnAppear)
    }
    .onChange(of: refreshTrigger) { _, _ in
      Task {
        await refreshLibraries(forceMetrics: true)
      }
    }
    .onChange(of: dashboard.libraryIds) { _, newValue in
      guard selectionEnabled, selectedLibraryIds != newValue else { return }
      withAnimation {
        selectedLibraryIds = newValue
      }
    }
    .onDisappear {
      if selectionEnabled, dashboard.libraryIds != selectedLibraryIds {
        withAnimation {
          DashboardLibrarySelectionStore.updateCurrentSelection(selectedLibraryIds)
        }
      }
    }
  }

  func refreshLibraries() async {
    await refreshLibraries(forceMetrics: true)
  }

  func refreshLibraries(forceMetrics: Bool) async {
    withAnimation {
      isLoading = true
    }
    await loadLibraryItems()
    await LibraryManager.shared.refreshLibraries()
    await loadLibraryItems()
    await triggerMetricsUpdate(force: forceMetrics)
    await loadLibraryItems()
    withAnimation {
      isLoading = false
    }
  }

  private func loadLibraryItems() async {
    guard !current.instanceId.isEmpty else {
      clearLibraryItemsIfNeeded()
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedLibraries = try await database.fetchSidebarLibraries(instanceId: current.instanceId)
      let loadedAllLibrariesEntry = try await database.fetchAllLibrariesItem(
        instanceId: current.instanceId
      )

      applyLibraryItems(
        libraries: loadedLibraries,
        allLibrariesEntry: loadedAllLibrariesEntry
      )
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func clearLibraryItemsIfNeeded() {
    guard !libraries.isEmpty || allLibrariesEntry != nil else { return }

    withAnimation {
      libraries = []
      allLibrariesEntry = nil
    }
  }

  private func applyLibraryItems(
    libraries loadedLibraries: [SidebarLibraryItem],
    allLibrariesEntry loadedAllLibrariesEntry: SidebarLibraryItem?
  ) {
    guard libraries != loadedLibraries || allLibrariesEntry != loadedAllLibrariesEntry else {
      return
    }

    withAnimation {
      if libraries != loadedLibraries {
        libraries = loadedLibraries
      }
      if allLibrariesEntry != loadedAllLibrariesEntry {
        allLibrariesEntry = loadedAllLibrariesEntry
      }
    }
  }

  private func triggerMetricsUpdate(force: Bool) async {
    guard loadMetrics, current.isAdmin && !isOffline, !current.instanceId.isEmpty else { return }

    let shouldLoad = force || alwaysRefreshMetrics || needsMetricsReload()

    guard shouldLoad else { return }

    if isLoadingMetrics {
      return
    }

    isLoadingMetrics = true

    let libraryIds = libraries.map(\.libraryId)

    let metricsByLibrary = await metricsLoader.refreshMetrics(
      instanceId: current.instanceId,
      libraryIds: libraryIds
    )

    do {
      let database = try await DatabaseOperator.database()
      try await database.updateLibraryMetrics(
        instanceId: current.instanceId,
        metricsByLibrary: metricsByLibrary
      )
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    isLoadingMetrics = false
  }

  private func needsMetricsReload() -> Bool {
    guard !libraries.isEmpty else { return false }

    if allLibrariesEntry == nil || !hasAllLibrariesMetrics(allLibrariesEntry) {
      return true
    }

    return libraries.contains { !hasMetrics($0) }
  }

  @ViewBuilder
  private func allLibrariesRowView() -> some View {
    let isSelected = selectedLibraryIds.isEmpty

    let rowContent = HStack(spacing: 12) {
      LibraryRowTextContent(
        name: String(localized: "All Libraries"),
        fileSize: allLibrariesEntry?.fileSize,
        metricsText: current.isAdmin
          ? allLibrariesEntry.flatMap { LibraryMetricsText.allLibrariesMetrics(for: $0) } : nil
      )

      Spacer()

      if selectionEnabled {
        LibrarySelectionIndicator(isSelected: isSelected)
      }
    }
    .contentShape(Rectangle())

    Group {
      if selectionEnabled {
        Button {
          selectAllLibraries()
        } label: {
          rowContent
        }
        .buttonStyle(.plain)
      } else {
        rowContent
      }
    }
    .contextMenu {
      if current.isAdmin && !isOffline {
        allLibrariesContextMenu()
      }
    }
  }

  private func handleLibrarySelection(for libraryId: String) {
    var currentIds = selectedLibraryIds
    let isSelected = currentIds.contains(libraryId)
    if isSelected {
      currentIds.removeAll { $0 == libraryId }
    } else if !currentIds.contains(libraryId) {
      currentIds.append(libraryId)
    }

    var seen = Set<String>()
    selectedLibraryIds = currentIds.filter { seen.insert($0).inserted }
  }

  private func selectAllLibraries() {
    selectedLibraryIds = []
  }

  @ViewBuilder
  private func allLibrariesContextMenu() -> some View {
    Button {
      performGlobalAction(
        notificationMessage: String(localized: "library.list.notify.scanAllStarted")
      ) {
        try await scanAllLibraries(deep: false)
      }
    } label: {
      Label(String(localized: "Scan All Libraries"), systemImage: "arrow.clockwise")
    }

    Button {
      performGlobalAction(
        notificationMessage: String(localized: "library.list.notify.scanAllDeepStarted")
      ) {
        try await scanAllLibraries(deep: true)
      }
    } label: {
      Label(
        String(localized: "Scan All Libraries (Deep)"),
        systemImage: "arrow.triangle.2.circlepath"
      )
    }

    Button {
      performGlobalAction(
        notificationMessage: String(localized: "library.list.notify.trashAllEmptied")
      ) {
        try await emptyTrashAllLibraries()
      }
    } label: {
      Label(String(localized: "Empty Trash for All Libraries"), systemImage: "trash.slash")
    }
  }

  // MARK: - Helper Functions

  private func hasMetrics(_ library: SidebarLibraryItem) -> Bool {
    library.seriesCount != nil || library.booksCount != nil || library.fileSize != nil
      || library.sidecarsCount != nil
  }

  private func hasAllLibrariesMetrics(_ entry: SidebarLibraryItem?) -> Bool {
    guard let entry else { return false }
    return entry.seriesCount != nil || entry.booksCount != nil || entry.fileSize != nil
      || entry.sidecarsCount != nil || entry.collectionsCount != nil
      || entry.readlistsCount != nil
  }

  // MARK: - Library Actions

  private func scanAllLibraries(deep: Bool) async throws {
    for library in libraries {
      try await LibraryService.scanLibrary(id: library.libraryId, deep: deep)
    }
  }

  private func emptyTrashAllLibraries() async throws {
    for library in libraries {
      try await LibraryService.emptyTrash(id: library.libraryId)
    }
  }

  private func performGlobalAction(
    notificationMessage: String? = nil,
    _ action: @escaping () async throws -> Void
  ) {
    Task {
      do {
        try await action()
        if let notificationMessage {
          ErrorManager.shared.notify(message: notificationMessage)
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
