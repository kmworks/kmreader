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
  let isSingleSelectionMode: Bool
  let loadMetrics: Bool
  let alwaysRefreshMetrics: Bool
  let forceMetricsOnAppear: Bool
  let enablePullToRefresh: Bool
  let onLibrarySelected: ((String?) -> Void)?
  let onEditLibrary: ((String) -> Void)?
  let onDeleteLibrary: ((LibrarySelection) -> Void)?
  let refreshTrigger: Int

  private let metricsLoader = LibraryMetricsLoader.shared

  init(
    selectionEnabled: Bool = false,
    isSingleSelectionMode: Bool = false,
    loadMetrics: Bool = true,
    alwaysRefreshMetrics: Bool = false,
    forceMetricsOnAppear: Bool = true,
    enablePullToRefresh: Bool = true,
    onLibrarySelected: ((String?) -> Void)? = nil,
    onEditLibrary: ((String) -> Void)? = nil,
    onDeleteLibrary: ((LibrarySelection) -> Void)? = nil,
    refreshTrigger: Int = 0
  ) {
    let initialSelection = AppConfig.dashboard.libraryIds
    self.selectionEnabled = selectionEnabled
    self.isSingleSelectionMode = isSingleSelectionMode
    self.loadMetrics = loadMetrics
    self.alwaysRefreshMetrics = alwaysRefreshMetrics
    self.forceMetricsOnAppear = forceMetricsOnAppear
    self.enablePullToRefresh = enablePullToRefresh
    self.onLibrarySelected = onLibrarySelected
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
              isSingleSelectionMode: isSingleSelectionMode,
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
    .onChange(of: isSingleSelectionMode) { _, newValue in
      guard selectionEnabled, newValue, selectedLibraryIds.count > 1 else { return }
      withAnimation {
        selectedLibraryIds = Array(selectedLibraryIds.prefix(1))
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
    let hasAllEntry = allLibrariesEntry != nil

    let metricsByLibrary = await metricsLoader.refreshMetrics(
      instanceId: current.instanceId,
      libraryIds: libraryIds,
      ensureAllLibrariesEntry: hasAllEntry
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
    let entry = allLibrariesEntry
    let metricsView = allLibrariesMetricsView(entry)
    let fileSizeText = entry?.fileSize.map { formatFileSize($0) } ?? ""

    let rowContent = HStack(spacing: 12) {
      rowTextContent(
        name: String(localized: "All Libraries"),
        fileSizeText: fileSizeText,
        metricsView: current.isAdmin ? metricsView : nil
      )

      Spacer()

      if selectionEnabled {
        selectionIndicator(isSelected: isSelected)
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
    if isSingleSelectionMode {
      selectedLibraryIds = [libraryId]
      onLibrarySelected?(libraryId)
      return
    }

    var currentIds = selectedLibraryIds
    let isSelected = currentIds.contains(libraryId)
    if isSelected {
      currentIds.removeAll { $0 == libraryId }
    } else if !currentIds.contains(libraryId) {
      currentIds.append(libraryId)
    }

    var seen = Set<String>()
    selectedLibraryIds = currentIds.filter { seen.insert($0).inserted }
    onLibrarySelected?(isSelected ? nil : libraryId)
  }

  private func selectAllLibraries() {
    selectedLibraryIds = []
    onLibrarySelected?("")
  }

  private func rowTextContent(
    name: String,
    fileSizeText: String,
    metricsView: Text?
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(name)
          .font(.headline)
        if !fileSizeText.isEmpty {
          Text(fileSizeText)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      if let metricsView {
        metricsView
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private func selectionIndicator(isSelected: Bool) -> some View {
    Image(systemName: selectionIndicatorName(isSelected: isSelected))
      .foregroundStyle(isSelected ? Color.primary : .secondary)
      .font(.title3)
      .animation(.default, value: isSelected)
  }

  private func selectionIndicatorName(isSelected: Bool) -> String {
    if isSingleSelectionMode {
      return isSelected ? "largecircle.fill.circle" : "circle"
    }
    return isSelected ? "checkmark.circle.fill" : "circle"
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

  private func joinText(_ parts: [Text], separator: String) -> Text? {
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { result, part in
      result + Text(separator) + part
    }
  }

  private func formatFileSize(_ bytes: Double) -> String {
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
  }

  private func hasAllLibrariesMetrics(_ entry: SidebarLibraryItem?) -> Bool {
    guard let entry else { return false }
    return entry.seriesCount != nil || entry.booksCount != nil || entry.fileSize != nil
      || entry.sidecarsCount != nil || entry.collectionsCount != nil
      || entry.readlistsCount != nil
  }

  private func allLibrariesMetricsView(_ entry: SidebarLibraryItem?) -> Text? {
    guard let entry else { return nil }
    var lines: [Text] = []

    // First line: series, books, sidecars
    var firstLineParts: [Text] = []
    if let seriesCount = entry.seriesCount {
      firstLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.series", defaultValue: "%lld series"),
            Int(seriesCount))))
    }
    if let booksCount = entry.booksCount {
      firstLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.books", defaultValue: "%lld books"),
            Int(booksCount))))
    }
    if let sidecarsCount = entry.sidecarsCount {
      firstLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.sidecars", defaultValue: "%lld sidecars"),
            Int(sidecarsCount))))
    }
    if let firstLine = joinText(firstLineParts, separator: " · ") {
      lines.append(firstLine)
    }

    // Second line: collections, readlists
    var secondLineParts: [Text] = []
    if let collectionsCount = entry.collectionsCount {
      secondLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.collections", defaultValue: "%lld collections"),
            Int(collectionsCount))))
    }
    if let readlistsCount = entry.readlistsCount {
      secondLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.readlists", defaultValue: "%lld read lists"),
            Int(readlistsCount))))
    }
    if let secondLine = joinText(secondLineParts, separator: " · ") {
      lines.append(secondLine)
    }

    return joinText(lines, separator: "\n")
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
