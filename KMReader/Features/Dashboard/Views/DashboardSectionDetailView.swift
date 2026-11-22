//
// DashboardSectionDetailView.swift
//
//

import SwiftUI

@MainActor
struct DashboardSectionDetailView: View {
  let section: DashboardSection

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("dashboardSectionDetailLayout") private var browseLayout: BrowseLayoutMode = .grid
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var pagination = PaginationState<IdentifiedString>(pageSize: 50)
  @State private var isLoading = false
  @State private var isQueueingLatestOffline = false
  @State private var isQueueingAllOffline = false
  @State private var hasLoadedInitial = false
  @State private var needsRefreshAfterCurrentLoad = false
  @State private var selectedItemIds: Set<String> = []
  @State private var isSelectionMode = false
  @State private var batchController = BatchOperationController()
  @State private var showReadListPicker = false
  @State private var showCollectionPicker = false
  @State private var showBookBatchEditor = false
  @State private var showSeriesBatchEditor = false
  @State private var showDeleteConfirmation = false

  private var isQueueingOffline: Bool {
    isQueueingLatestOffline || isQueueingAllOffline
  }

  private var effectiveLibraryIds: [String] {
    LibraryScopeSelectionStore.shared.effectiveLibraryIds(pinned: dashboard.libraryIds)
  }

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    Binding(
      get: { browseLayout },
      set: { setBrowseLayout($0) }
    )
  }

  private var supportsSelectionMode: Bool {
    #if os(tvOS)
      return false
    #else
      return true
    #endif
  }

  private var loadedItemIds: [String] {
    pagination.items.map(\.id)
  }

  private var selectedItemIdsInDisplayOrder: [String] {
    loadedItemIds.filter(selectedItemIds.contains)
  }

  private var addLabel: String {
    switch section.contentKind {
    case .books:
      return String(localized: "Add to Read List")
    case .series:
      return String(localized: "Add to Collection")
    }
  }

  private var komfMatchLabel: String? {
    guard section.contentKind == .series, KomfIntegrationStore.shared.isAvailable else { return nil }
    return String(localized: "Match with komf")
  }

  private var deleteAlertTitle: LocalizedStringKey {
    switch section.contentKind {
    case .books:
      return "Delete Book Files"
    case .series:
      return "Delete Series Files"
    }
  }

  private var deleteConfirmationMessage: LocalizedStringKey {
    switch section.contentKind {
    case .books:
      return "batch.books.deleteConfirmation \(selectedItemIds.count)"
    case .series:
      return "batch.series.deleteConfirmation \(selectedItemIds.count)"
    }
  }

  private var emptyStateIcon: String {
    switch section.contentKind {
    case .books:
      return ContentIcon.book
    case .series:
      return ContentIcon.series
    }
  }

  private var emptyStateTitle: LocalizedStringKey {
    switch section.contentKind {
    case .books:
      return LocalizedStringKey("No books found")
    case .series:
      return LocalizedStringKey("No series found")
    }
  }

  private var emptyStateMessage: LocalizedStringKey {
    LocalizedStringKey("Try selecting a different library.")
  }

  var body: some View {
    ScrollView {
      #if os(tvOS)
        HStack {
          LayoutModeMenu(selection: browseLayoutBinding)
          Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)

        if section.supportsDownloadLatest {
          Menu {
            downloadMenuItems
          } label: {
            Label(
              String(localized: "Download"),
              systemImage: AppIcon.download
            )
          }
          .disabled(isOffline || isQueueingOffline)
          .padding(.horizontal)
        }
      #endif

      #if os(iOS) || os(macOS)
        if !isSelectionMode && !isOffline {
          HStack {
            Spacer()
            Button {
              withAnimation { isSelectionMode = true }
            } label: {
              Image(systemName: "checkmark.circle")
            }
            .adaptiveButtonStyle(.bordered)
            .optimizedControlSize()
          }
          .padding(.horizontal)
        }

        if isSelectionMode {
          SelectionActionsToolbar(
            selectedCount: selectedItemIds.count,
            totalCount: loadedItemIds.count,
            isSubmitting: batchController.isRunning,
            completedCount: batchController.completedCount,
            runningTotalCount: batchController.totalCount,
            addLabel: addLabel,
            editLabel: String(localized: "Edit Metadata"),
            deleteLabel: current.isAdmin ? String(localized: "Delete Files") : nil,
            komfMatchLabel: komfMatchLabel,
            onSelectAll: toggleSelectAll,
            onMarkRead: {
              Task { await markSelected(read: true) }
            },
            onMarkUnread: {
              Task { await markSelected(read: false) }
            },
            onAdd: showMembershipPicker,
            onEdit: showBatchEditor,
            onDelete: { showDeleteConfirmation = true },
            onKomfMatch: {
              Task { await matchSelectedWithKomf() }
            },
            onCancel: exitSelectionMode
          )
          .padding(.horizontal)
        }
      #endif

      BrowseStateView(
        isLoading: isLoading,
        isEmpty: pagination.isEmpty,
        emptyIcon: emptyStateIcon,
        emptyTitle: emptyStateTitle,
        emptyMessage: emptyStateMessage,
        onRetry: {
          Task {
            await loadItems(refresh: true)
          }
        }
      ) {
        contentView
      }
      .padding()
    }
    .inlineNavigationTitle(section.displayName)
    .task {
      guard !hasLoadedInitial else { return }
      hasLoadedInitial = true
      await loadItems(refresh: true)
    }
    .refreshable {
      await loadItems(refresh: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .dashboardSectionsShouldReload)) { notification in
      guard let command = DashboardSectionRefreshNotifier.reloadCommand(from: notification) else {
        return
      }
      guard command.includes(section) else { return }
      Task { await revalidateItems() }
    }
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookIds: selectedItemIdsInDisplayOrder,
        onSelect: addSelectedToReadList,
        onCreate: { _ in finishBatchSelection([]) }
      )
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesIds: selectedItemIdsInDisplayOrder,
        onSelect: addSelectedToCollection,
        onCreate: { _ in finishBatchSelection([]) }
      )
    }
    .sheet(isPresented: $showBookBatchEditor) {
      BookBatchEditSheet(
        bookIds: selectedItemIdsInDisplayOrder,
        onCompleted: finishBatchSelection
      )
    }
    .sheet(isPresented: $showSeriesBatchEditor) {
      SeriesBatchEditSheet(
        seriesIds: selectedItemIdsInDisplayOrder,
        onCompleted: finishBatchSelection
      )
    }
    .alert(deleteAlertTitle, isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task { await deleteSelectedFiles() }
      }
    } message: {
      Text(deleteConfirmationMessage)
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Menu {
            Picker(selection: browseLayoutBinding) {
              ForEach(BrowseLayoutMode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.iconName).tag(mode)
              }
            } label: {
              EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if section.supportsDownloadLatest {
              Divider()
              downloadMenuItems
            }
          } label: {
            if isQueueingOffline {
              LoadingIcon()
            } else {
              Image(systemName: AppIcon.more)
            }
          }
        }
      }
    #endif
  }

  @ViewBuilder
  private var downloadMenuItems: some View {
    Button {
      queueLatestBooksOffline()
    } label: {
      Label(
        String(localized: "dashboard.downloadLatest20", defaultValue: "Download Latest 20 Books"),
        systemImage: AppIcon.download
      )
    }
    .disabled(isOffline || isQueueingOffline)

    if section.supportsDownloadAll {
      Button {
        queueAllBooksOffline()
      } label: {
        Label(
          String(localized: "dashboard.downloadAll", defaultValue: "Download All"),
          systemImage: AppIcon.download
        )
      }
      .disabled(isOffline || isQueueingOffline)
    }
  }

  @ViewBuilder
  private var contentView: some View {
    switch section.contentKind {
    case .books:
      bookContentView
    case .series:
      seriesContentView
    }
  }

  @ViewBuilder
  private var bookContentView: some View {
    switch browseLayout {
    case .grid, .largeGrid:
      LazyVGrid(columns: columns, spacing: spacing) {
        ForEach(pagination.items) { book in
          Group {
            if isSelectionMode {
              BookSelectionItemView(
                bookId: book.id,
                layout: browseLayout,
                selectedBookIds: $selectedItemIds,
                cardWidth: browseLayout.cardWidth,
                showSeriesTitle: true
              )
            } else {
              BookQueryItemView(
                bookId: book.id,
                layout: browseLayout,
                showSeriesTitle: true,
                cardWidth: browseLayout.cardWidth,
                onItemMissing: {
                  removeItem(id: book.id)
                }
              )
            }
          }
          .onAppear {
            if pagination.shouldLoadMore(after: book) {
              Task { await loadItems(refresh: false) }
            }
          }
        }
      }
    case .list:
      LazyVStack {
        ForEach(pagination.items) { book in
          Group {
            if isSelectionMode {
              BookSelectionItemView(
                bookId: book.id,
                layout: .list,
                selectedBookIds: $selectedItemIds,
                showSeriesTitle: true
              )
            } else {
              BookQueryItemView(
                bookId: book.id,
                layout: .list,
                showSeriesTitle: true,
                onItemMissing: {
                  removeItem(id: book.id)
                }
              )
            }
          }
          .onAppear {
            if pagination.shouldLoadMore(after: book) {
              Task { await loadItems(refresh: false) }
            }
          }
          if !pagination.isLast(book) {
            Divider()
          }
        }
      }
    }
  }

  @ViewBuilder
  private var seriesContentView: some View {
    switch browseLayout {
    case .grid, .largeGrid:
      LazyVGrid(columns: columns, spacing: spacing) {
        ForEach(pagination.items) { series in
          Group {
            if isSelectionMode {
              SeriesSelectionItemView(
                seriesId: series.id,
                layout: browseLayout,
                selectedSeriesIds: $selectedItemIds,
                cardWidth: browseLayout.cardWidth
              )
            } else {
              SeriesQueryItemView(
                seriesId: series.id,
                layout: browseLayout,
                cardWidth: browseLayout.cardWidth,
                onItemMissing: {
                  removeItem(id: series.id)
                }
              )
            }
          }
          .onAppear {
            if pagination.shouldLoadMore(after: series) {
              Task { await loadItems(refresh: false) }
            }
          }
        }
      }
    case .list:
      LazyVStack {
        ForEach(pagination.items) { series in
          Group {
            if isSelectionMode {
              SeriesSelectionItemView(
                seriesId: series.id,
                layout: .list,
                selectedSeriesIds: $selectedItemIds
              )
            } else {
              SeriesQueryItemView(
                seriesId: series.id,
                layout: .list,
                onItemMissing: {
                  removeItem(id: series.id)
                }
              )
            }
          }
          .onAppear {
            if pagination.shouldLoadMore(after: series) {
              Task { await loadItems(refresh: false) }
            }
          }
          if !pagination.isLast(series) {
            Divider()
          }
        }
      }
    }
  }

  private func toggleSelectAll() {
    if selectedItemIds.count == loadedItemIds.count {
      selectedItemIds.removeAll()
    } else {
      selectedItemIds = Set(loadedItemIds)
    }
  }

  private func showMembershipPicker() {
    switch section.contentKind {
    case .books:
      showReadListPicker = true
    case .series:
      showCollectionPicker = true
    }
  }

  private func showBatchEditor() {
    switch section.contentKind {
    case .books:
      showBookBatchEditor = true
    case .series:
      showSeriesBatchEditor = true
    }
  }

  private func markSelected(read: Bool) async {
    guard !selectedItemIds.isEmpty, !batchController.isRunning else { return }

    let outcome: BatchOperationOutcome
    switch section.contentKind {
    case .books:
      outcome = await BookBatchActions.mark(
        ids: Array(selectedItemIds),
        read: read,
        instanceId: current.instanceId,
        using: batchController
      )
    case .series:
      outcome = await SeriesBatchActions.mark(
        ids: Array(selectedItemIds),
        read: read,
        using: batchController
      )
    }
    finishBatchSelection(Set(outcome.failed))
  }

  private func addSelectedToReadList(readListId: String) {
    let bookIds = selectedItemIdsInDisplayOrder
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

  private func addSelectedToCollection(collectionId: String) {
    let seriesIds = selectedItemIdsInDisplayOrder
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
    guard !selectedItemIds.isEmpty, !batchController.isRunning else { return }

    let outcome: BatchOperationOutcome
    switch section.contentKind {
    case .books:
      outcome = await BookBatchActions.deleteFiles(
        ids: Array(selectedItemIds),
        instanceId: current.instanceId,
        using: batchController
      )
    case .series:
      outcome = await SeriesBatchActions.deleteFiles(
        ids: Array(selectedItemIds),
        instanceId: current.instanceId,
        using: batchController
      )
    }
    finishBatchSelection(Set(outcome.failed))
  }

  private func matchSelectedWithKomf() async {
    guard section.contentKind == .series,
      !selectedItemIds.isEmpty,
      !batchController.isRunning
    else { return }

    let outcome = await SeriesBatchActions.matchWithKomf(
      ids: Array(selectedItemIds),
      using: batchController
    )
    finishBatchSelection(Set(outcome.failed))
  }

  private func finishBatchSelection(_ failedIds: Set<String>) {
    withAnimation {
      selectedItemIds = failedIds
      isSelectionMode = !failedIds.isEmpty
    }
    Task { await revalidateItems() }
  }

  private func exitSelectionMode() {
    withAnimation {
      selectedItemIds.removeAll()
      isSelectionMode = false
    }
  }

  func loadItems(refresh: Bool) async {
    guard !isLoading else {
      if refresh {
        needsRefreshAfterCurrentLoad = true
      }
      return
    }
    guard refresh || pagination.hasMorePages else { return }

    if refresh {
      withAnimation {
        isLoading = true
        pagination.reset()
      }
    } else {
      withAnimation {
        isLoading = true
      }
    }

    let libraryIds = effectiveLibraryIds
    let instanceId = AppConfig.current.instanceId

    if AppConfig.isOffline {
      let ids: [String]
      switch section.contentKind {
      case .books:
        ids = await section.fetchOfflineBookIds(
          libraryIds: libraryIds,
          offset: pagination.currentPage * pagination.pageSize,
          limit: pagination.pageSize
        )
      case .series:
        ids = await section.fetchOfflineSeriesIds(
          libraryIds: libraryIds,
          offset: pagination.currentPage * pagination.pageSize,
          limit: pagination.pageSize
        )
      }
      applyPage(ids: ids, moreAvailable: ids.count == pagination.pageSize)
      updateWidgetDataIfNeeded(
        ids: ids,
        refresh: refresh,
        instanceId: instanceId,
        libraryIds: libraryIds
      )
    } else {
      do {
        switch section.contentKind {
        case .books:
          if let page = try await section.fetchBooks(
            libraryIds: libraryIds,
            page: pagination.currentPage,
            size: pagination.pageSize
          ) {
            let ids = page.content.map { $0.id }
            applyPage(ids: ids, moreAvailable: !page.last)
            if refresh {
              updateWidgetDataIfNeeded(
                books: page.content,
                instanceId: instanceId,
                libraryIds: libraryIds
              )
            }
          }
        case .series:
          if let page = try await section.fetchSeries(
            libraryIds: libraryIds,
            page: pagination.currentPage,
            size: pagination.pageSize
          ) {
            let ids = page.content.map { $0.id }
            applyPage(ids: ids, moreAvailable: !page.last)
            if refresh {
              updateWidgetDataIfNeeded(
                series: page.content,
                instanceId: instanceId,
                libraryIds: libraryIds
              )
            }
          }
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }

    finishLoading()
  }

  private func finishLoading() {
    withAnimation {
      isLoading = false
    }

    guard needsRefreshAfterCurrentLoad else { return }
    needsRefreshAfterCurrentLoad = false
    Task {
      await loadItems(refresh: true)
    }
  }

  private func removeItem(id: String) {
    withAnimation {
      _ = pagination.removeItems(withIDs: [id])
    }
  }

  private func updateWidgetDataIfNeeded(books: [Book], instanceId: String, libraryIds: [String]) {
    section.widgetDataTarget?.update(books: books, instanceId: instanceId, libraryIds: libraryIds)
  }

  private func updateWidgetDataIfNeeded(series: [Series], instanceId: String, libraryIds: [String]) {
    section.widgetDataTarget?.update(series: series, instanceId: instanceId, libraryIds: libraryIds)
  }

  private func updateWidgetDataIfNeeded(
    ids: [String],
    refresh: Bool,
    instanceId: String,
    libraryIds: [String]
  ) {
    guard refresh, let target = section.widgetDataTarget else { return }
    guard !instanceId.isEmpty else { return }

    Task {
      await target.update(ids: ids, instanceId: instanceId, libraryIds: libraryIds)
    }
  }

  private func queueLatestBooksOffline() {
    guard section.supportsDownloadLatest, !isOffline else { return }
    guard !isQueueingOffline else { return }

    withAnimation {
      isQueueingLatestOffline = true
    }
    let libraryIds = effectiveLibraryIds
    let instanceId = AppConfig.current.instanceId

    Task {
      defer {
        Task { @MainActor in
          withAnimation {
            isQueueingLatestOffline = false
          }
        }
      }

      do {
        let page = try await section.fetchBooks(libraryIds: libraryIds, page: 0, size: 20)
        let ids = page?.content.map(\.id) ?? []
        let queuedCount =
          ids.isEmpty
          ? 0
          : await DatabaseOperator.databaseIfConfigured()?.queueBooksOffline(
            bookIds: ids,
            instanceId: instanceId
          ) ?? 0

        notifyOfflineQueueResult(
          queuedCount: queuedCount,
          foundBooks: !ids.isEmpty,
          instanceId: instanceId
        )
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func queueAllBooksOffline() {
    guard section.supportsDownloadAll, !isOffline else { return }
    guard !isQueueingOffline else { return }

    withAnimation {
      isQueueingAllOffline = true
    }
    let libraryIds = effectiveLibraryIds
    let instanceId = AppConfig.current.instanceId

    Task {
      defer {
        Task { @MainActor in
          withAnimation {
            isQueueingAllOffline = false
          }
        }
      }

      do {
        let result = try await queueAllBookPagesOffline(
          libraryIds: libraryIds,
          instanceId: instanceId
        )

        notifyOfflineQueueResult(
          queuedCount: result.queuedCount,
          foundBooks: result.foundBooks,
          instanceId: instanceId
        )
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func notifyOfflineQueueResult(queuedCount: Int, foundBooks: Bool, instanceId: String) {
    guard foundBooks else {
      ErrorManager.shared.notify(
        message: String(localized: "No books found to queue for offline reading.")
      )
      return
    }

    if queuedCount > 0 {
      OfflineManager.shared.triggerSync(instanceId: instanceId)
      ErrorManager.shared.notify(
        message: String(
          format: String(localized: "Queued %lld books for offline reading."),
          Int64(queuedCount)
        )
      )
    } else {
      ErrorManager.shared.notify(
        message: String(localized: "No new books were added to the offline queue.")
      )
    }
  }

  private func queueAllBookPagesOffline(
    libraryIds: [String],
    instanceId: String,
    pageSize: Int = 100
  ) async throws -> (queuedCount: Int, foundBooks: Bool) {
    guard !instanceId.isEmpty else { return (0, false) }

    var pageIndex = 0
    var queuedCount = 0
    var foundBooks = false

    while true {
      guard
        let page = try await section.fetchBooks(
          libraryIds: libraryIds,
          page: pageIndex,
          size: pageSize
        )
      else {
        break
      }

      foundBooks = foundBooks || !page.content.isEmpty
      let ids = page.content.map(\.id)
      queuedCount +=
        await DatabaseOperator.databaseIfConfigured()?.queueBooksOffline(
          bookIds: ids,
          instanceId: instanceId
        ) ?? 0

      guard !page.last else { break }
      pageIndex += 1
    }

    return (queuedCount, foundBooks)
  }

  private func applyPage(ids: [String], moreAvailable: Bool) {
    let wrappedIds = ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.applyPage(wrappedIds)
    }
    pagination.advance(moreAvailable: moreAvailable)
  }

  /// Notification-driven refresh: re-fetches the already-loaded page window
  /// and replaces items in place so the scroll position and loaded pages are
  /// preserved. Explicit user actions still use `loadItems(refresh: true)`.
  private func revalidateItems() async {
    guard !isLoading else { return }
    let windowSize = pagination.currentPage * pagination.pageSize
    guard windowSize > 0 else {
      await loadItems(refresh: true)
      return
    }

    let loadID = pagination.loadID
    withAnimation {
      isLoading = true
    }
    defer {
      if loadID == pagination.loadID {
        withAnimation {
          isLoading = false
        }
      }
    }

    let libraryIds = effectiveLibraryIds

    if AppConfig.isOffline {
      let ids: [String]
      switch section.contentKind {
      case .books:
        ids = await section.fetchOfflineBookIds(
          libraryIds: libraryIds,
          offset: 0,
          limit: windowSize
        )
      case .series:
        ids = await section.fetchOfflineSeriesIds(
          libraryIds: libraryIds,
          offset: 0,
          limit: windowSize
        )
      }
      guard loadID == pagination.loadID else { return }
      applyRevalidatedWindow(ids: ids, moreAvailable: ids.count == windowSize)
    } else {
      do {
        switch section.contentKind {
        case .books:
          if let page = try await section.fetchBooks(
            libraryIds: libraryIds,
            page: 0,
            size: windowSize
          ) {
            guard loadID == pagination.loadID else { return }
            applyRevalidatedWindow(ids: page.content.map { $0.id }, moreAvailable: !page.last)
          }
        case .series:
          if let page = try await section.fetchSeries(
            libraryIds: libraryIds,
            page: 0,
            size: windowSize
          ) {
            guard loadID == pagination.loadID else { return }
            applyRevalidatedWindow(ids: page.content.map { $0.id }, moreAvailable: !page.last)
          }
        }
      } catch {
        // Silent: notification-driven revalidation must not interrupt with alerts.
      }
    }
  }

  private func applyRevalidatedWindow(ids: [String], moreAvailable: Bool) {
    let wrappedIds = ids.map(IdentifiedString.init)
    withAnimation {
      _ = pagination.replaceItems(wrappedIds, moreAvailable: moreAvailable)
    }
  }

  private func setBrowseLayout(_ layout: BrowseLayoutMode) {
    guard browseLayout != layout else { return }
    withAnimation {
      browseLayout = layout
    }
  }
}
