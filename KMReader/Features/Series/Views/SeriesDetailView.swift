//
// SeriesDetailView.swift
//
//

import Flow
import SwiftUI

struct SeriesDetailView: View {
  let seriesId: String

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @Environment(\.dismiss) private var dismiss
  @Environment(\.readerActions) private var readerActions
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var item: SeriesDisplayItem?
  @State private var loadedSeriesId: String?
  @State private var hasError = false
  @State private var collections: [SidebarCollectionItem] = []
  @State private var bookViewModel = BookViewModel()
  @State private var showDeleteConfirmation = false
  @State private var showCollectionPicker = false
  @State private var showEditSheet = false
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  @State private var showKomfIdentify = false
  @State private var showKomfResetConfirmation = false
  @State private var readingTargetBook: Book?
  @State private var readingTargetInstanceId: String?
  @State private var readingTargetIsOffline: Bool?
  @State private var isResolvingReadingTarget = false
  @State private var readingTargetResolutionID = 0
  /// Gates publishing to the shared reading-bar context: late async
  /// completions must not resurrect the accessory after the view disappeared.
  @State private var isReadingBarVisible = false
  /// Measured detail-column width driving the single/two-column layout switch.
  /// Defaults wide where the wide layout can engage (iPad, macOS) so the first
  /// frame doesn't flash the single column.
  #if os(macOS)
    @State private var detailContentWidth: CGFloat = .infinity
  #else
    @State private var detailContentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif
  @AppStorage("seriesBookBrowseOptions") private var seriesBookBrowseOptions: BookBrowseOptions =
    BookBrowseOptions()

  private let readingBarContext = ReadingActionBarContext.shared

  init(seriesId: String) {
    self.seriesId = seriesId
  }

  private var series: Series? {
    item?.series
  }

  private var canMarkSeriesAsRead: Bool {
    guard let series else { return false }
    return series.booksUnreadCount > 0
  }

  private var canMarkSeriesAsUnread: Bool {
    guard let series else { return false }
    return (series.booksReadCount + series.booksInProgressCount) > 0
  }

  private var canRead: Bool {
    guard let series, !series.deleted else { return false }
    return (series.booksUnreadCount + series.booksInProgressCount) > 0
  }

  private var readLabel: String {
    if isResumingReading {
      return String(localized: "Resume Reading")
    } else {
      return String(localized: "Start Reading")
    }
  }

  private var isResumingReading: Bool {
    series?.hasStartedReading == true
  }

  private var navigationTitle: String {
    series?.metadata.title ?? String(localized: "Series")
  }

  private var shareURL: URL? {
    KomgaWebLinkBuilder.series(serverURL: current.serverURL, seriesId: seriesId)
  }

  private var shouldShowReadingBar: Bool {
    guard canRead else { return false }
    // Offline: only show when there is an actual downloadable book to resume;
    // otherwise the bar would just show the series title as a useless fallback.
    if isOffline {
      return readingTargetBookForCurrentContext != nil || isResolvingReadingTarget
    }
    return true
  }

  /// iPhone on iOS 26.1+ renders the continue-reading entry through the system
  /// tab bar bottom accessory; everywhere else (iPad, macOS, tvOS, older iOS)
  /// uses the inline header button instead.
  private var showsInlineReadingAction: Bool {
    guard shouldShowReadingBar else { return false }
    #if os(iOS)
      if !PlatformHelper.isPad, #available(iOS 26.1, *) {
        return false
      }
    #endif
    return true
  }

  /// The two-column layout engages only while the detail column is wide
  /// enough for it. iPad additionally requires regular width (a docked sidebar
  /// in portrait, or iPad mini portrait, narrows the column below the
  /// threshold); macOS decides by window width alone.
  private var usesWideLayout: Bool {
    #if os(iOS)
      return PlatformHelper.isPad && horizontalSizeClass == .regular
        && detailContentWidth >= LayoutConfig.detailWideLayoutMinimumWidth
    #elseif os(macOS)
      return detailContentWidth >= LayoutConfig.detailWideLayoutMinimumWidth
    #else
      return false
    #endif
  }

  private var readingTargetBookForCurrentContext: Book? {
    guard readingTargetInstanceId == current.instanceId, readingTargetIsOffline == isOffline else {
      return nil
    }
    return readingTargetBook
  }

  var body: some View {
    Group {
      if usesWideLayout {
        if let series = series {
          SeriesDetailWideLayoutView(
            series: series,
            item: item,
            collections: collections,
            seriesId: seriesId,
            availableWidth: detailContentWidth,
            bookViewModel: bookViewModel,
            showFilterSheet: $showFilterSheet,
            showSavedFilters: $showSavedFilters
          ) {
            seriesActions
          }
        } else if hasError {
          seriesLoadFailureView
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading) {
            if let series = series {
              VStack(alignment: .leading) {
                #if os(tvOS)
                  seriesToolbarContent
                    .padding(.vertical, 8)
                #endif

                SeriesDetailContentView(series: series) {
                  seriesActions
                }

                if item != nil {
                  DetailMembershipSection(collections: collections)
                }
              }
              .padding(.horizontal)

              if item != nil {
                BooksListViewForSeries(
                  seriesId: seriesId,
                  bookViewModel: bookViewModel,
                  showFilterSheet: $showFilterSheet,
                  showSavedFilters: $showSavedFilters
                )
              }
            } else if hasError {
              seriesLoadFailureView
            } else {
              ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
          .padding(.vertical)
        }
      }
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
      detailContentWidth = $0
    }
    .platformNavigationTitle(navigationTitle)
    .komgaHandoff(
      title: navigationTitle,
      url: KomgaWebLinkBuilder.series(serverURL: current.serverURL, seriesId: seriesId),
      scope: .browse
    )
    .onAppear {
      isReadingBarVisible = true
      syncReadingBarContext()
    }
    .onDisappear {
      isReadingBarVisible = false
      readingBarContext.clear(seriesId: seriesId)
    }
    #if os(iOS)
      .background {
        if #available(iOS 26.1, *) {
          // Hide the reading accessory as soon as the pop transition starts
          // (viewWillDisappear) instead of waiting for onDisappear, which only
          // fires after teardown. onDidAppear re-syncs so a cancelled
          // interactive pop restores the accessory.
          ViewLifecycleObserver(
            onWillDisappear: {
              isReadingBarVisible = false
              readingBarContext.clear(seriesId: seriesId)
            },
            onDidAppear: {
              isReadingBarVisible = true
              syncReadingBarContext()
            }
          )
        }
      }
    #endif
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          seriesToolbarContent
        }
      }
    #endif
    .alert("Delete Series?", isPresented: $showDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        deleteSeries()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete \(series?.metadata.title ?? "this series") from Komga.")
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesId: seriesId,
        onSelect: { collectionId in
          addToCollection(collectionId: collectionId)
        }
      )
    }
    .sheet(isPresented: $showEditSheet) {
      if let series = series {
        SeriesEditSheet(series: series)
          .onDisappear {
            Task {
              await refreshSeriesData()
            }
          }
      }
    }
    .sheet(isPresented: $showKomfIdentify) {
      if let series {
        KomfIdentifySheet(series: series)
      }
    }
    .alert("Reset Metadata with komf?", isPresented: $showKomfResetConfirmation) {
      Button("Reset", role: .destructive) {
        resetWithKomf()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "komf removes the metadata it wrote for \(series?.metadata.title ?? "this series"), including field locks and uploaded covers."
      )
    }
    .sheet(isPresented: $showSavedFilters) {
      SavedFiltersView(filterType: .seriesBooks)
    }
    .task {
      guard loadedSeriesId != seriesId else { return }
      loadedSeriesId = seriesId
      #if os(iOS) || os(macOS)
        Task {
          await KomfIntegrationStore.shared.refresh(isAdmin: current.isAdmin)
        }
      #endif
      await refreshSeriesData()
    }
    .onChange(of: current) {
      clearReadingTargetForContextChange()
      #if os(iOS) || os(macOS)
        Task {
          await KomfIntegrationStore.shared.refresh(isAdmin: current.isAdmin)
        }
      #endif
      Task {
        await refreshSeriesData()
      }
    }
    .onChange(of: isOffline) {
      clearReadingTargetForContextChange()
      Task {
        await refreshReadingTargetBook()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .seriesProjectionDidChange)) {
      notification in
      guard shouldRefreshForSeriesProjection(notification) else { return }
      Task {
        await refreshLocalSeriesData()
        await revalidateSeriesBooksIfNeeded(for: notification)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) {
      notification in
      guard shouldRefreshForBookProjection(notification) else { return }
      Task {
        await refreshLocalSeriesData()
        await revalidateSeriesBooksIfNeeded(for: notification)
      }
    }
  }
}

extension SeriesDetailView {
  private func refreshSeriesData() async {
    hasError = false
    await loadLocalSeries()
    await refreshReadingTargetBook(localOnly: true)
    do {
      _ = try await SyncService.syncSeriesDetail(seriesId: seriesId)
      await SyncService.syncSeriesCollections(seriesId: seriesId)
    } catch {
      if case APIError.notFound = error {
        dismiss()
      } else if item == nil {
        hasError = true
        ErrorManager.shared.alert(error: error)
      }
    }
    await loadLocalSeries()
    await refreshReadingTargetBook()
  }

  @ViewBuilder
  private var seriesLoadFailureView: some View {
    ContentUnavailableView {
      Label("Failed to load series details", systemImage: "exclamationmark.triangle")
    } actions: {
      Button(String(localized: "Retry")) {
        Task {
          await refreshSeriesData()
        }
      }
      .adaptiveButtonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func refreshLocalSeriesData() async {
    await loadLocalSeries()
    await refreshReadingTargetBook()
  }

  /// Pure reading-progress changes (e.g. reader closed) are applied by the
  /// item rows themselves from GRDB; the ID list is only revalidated when the
  /// change can alter membership or ordering for the current browse options.
  private func revalidateSeriesBooksIfNeeded(for notification: Notification) async {
    let reasons = ContentProjectionNotifier.changeReasons(from: notification)
    guard !reasons.isSubset(of: [.readingProgress]) || seriesBookBrowseOptions.isSensitiveToReadingProgress
    else { return }
    await bookViewModel.revalidateSeriesBooks(
      seriesId: seriesId,
      browseOpts: seriesBookBrowseOptions
    )
  }

  private func loadLocalSeries() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      collections = []
      return
    }
    item = try? await database.fetchSeriesDisplayItem(
      seriesId: seriesId,
      instanceId: current.instanceId
    )
    await loadCollections()
  }

  private func loadCollections() async {
    let instanceId = current.instanceId
    guard let collectionIds = item?.collectionIds, !instanceId.isEmpty, !collectionIds.isEmpty
    else {
      collections = []
      return
    }
    do {
      let database = try await DatabaseOperator.database()
      let loadedCollections = try await database.fetchSidebarCollections(
        instanceId: instanceId,
        collectionIds: Set(collectionIds)
      )
      if collections != loadedCollections {
        withAnimation {
          collections = loadedCollections
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func analyzeSeries() {
    Task {
      do {
        try await SeriesService.analyzeSeries(seriesId: seriesId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.analysisStarted"))
        await refreshSeriesData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func refreshSeriesMetadata() {
    Task {
      do {
        try await SeriesService.refreshMetadata(seriesId: seriesId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.metadataRefreshed"))
        await refreshSeriesData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func resetWithKomf() {
    guard let series else { return }
    Task {
      await KomfActions.reset(
        libraryId: series.libraryId,
        seriesId: series.id,
        seriesTitle: series.metadata.title.isEmpty ? series.name : series.metadata.title
      )
      await refreshSeriesData()
    }
  }

  private func markSeriesAsRead() {
    Task {
      do {
        try await SeriesService.markAsRead(seriesId: seriesId)
        _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
        try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
        await ContentProjectionNotifier.postSeriesBooksDidChange(
          seriesId: seriesId,
          reason: .readingProgress
        )
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Series read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.series.markedRead"))
        await refreshSeriesData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markSeriesAsUnread() {
    Task {
      do {
        try await SeriesService.markAsUnread(seriesId: seriesId)
        _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
        try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
        await ContentProjectionNotifier.postSeriesBooksDidChange(
          seriesId: seriesId,
          reason: .readingProgress
        )
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Series read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.series.markedUnread"))
        await refreshSeriesData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deleteSeries() {
    Task {
      do {
        if let series {
          try await SeriesDeletionService.deleteSeries(series, instanceId: current.instanceId)
        } else {
          try await SeriesDeletionService.deleteSeries(
            seriesId: seriesId,
            instanceId: current.instanceId
          )
        }
        ErrorManager.shared.notify(message: String(localized: "notification.series.deleted"))
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func continueReading() {
    Task {
      let instanceId = current.instanceId
      let offline = isOffline
      let resolvedBook = await resolveReadingTargetBook(instanceId: instanceId, isOffline: offline)
      guard instanceId == current.instanceId, offline == isOffline else { return }
      updateReadingTarget(resolvedBook, instanceId: instanceId, isOffline: offline)

      if let book = resolvedBook {
        readerActions.open(book: book, incognito: false)
      }
    }
  }

  private func addToCollection(collectionId: String) {
    Task {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: collectionId,
          seriesIds: [seriesId]
        )
        // Sync the collection to update its local series IDs
        _ = try? await SyncService.syncCollection(id: collectionId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        await refreshSeriesData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private var seriesActions: some View {
    if showsInlineReadingAction {
      SeriesReadingActionButton(
        caption: readingActionCaption,
        title: readingDisplayTitle,
        isResolving: isResolvingReadingTarget
      ) {
        continueReading()
      }
    }
    if let item {
      SeriesDownloadActionsSection(
        seriesId: item.seriesId,
        status: item.downloadStatus,
        policy: item.offlinePolicy,
        offlinePolicyLimit: item.offlinePolicyLimit,
        onMutationCompleted: {
          Task {
            await refreshSeriesData()
          }
        }
      )
    }
  }

  @ViewBuilder
  private var seriesToolbarContent: some View {
    Menu {
      #if os(iOS) || os(macOS)
        if let shareURL {
          ShareLink(item: shareURL, subject: Text(navigationTitle)) {
            Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
          }

          Divider()
        }
      #endif

      if current.isAdmin {
        Button {
          deferMenuActionPresentation { showEditSheet = true }
        } label: {
          Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button {
          analyzeSeries()
        } label: {
          Label("Analyze", systemImage: "waveform.path.ecg")
        }

        Button {
          refreshSeriesMetadata()
        } label: {
          Label("Refresh Metadata", systemImage: "arrow.clockwise")
        }

        #if os(iOS) || os(macOS)
          if KomfIntegrationStore.shared.isAvailable, let series {
            Divider()

            KomfMenu(
              libraryId: series.libraryId,
              seriesId: series.id,
              seriesTitle: series.metadata.title.isEmpty ? series.name : series.metadata.title,
              onIdentify: { showKomfIdentify = true },
              onReset: { showKomfResetConfirmation = true }
            )
          }
        #endif

        Divider()
      }

      Button {
        #if os(macOS)
          // Present in a standalone window: a view-attached sheet triggered
          // from an NSMenu action can wedge the app on macOS 15.
          PickerWindowOpener.shared.open(.collection(seriesId: seriesId))
        #else
          deferMenuActionPresentation { showCollectionPicker = true }
        #endif
      } label: {
        Label("Add to Collection", systemImage: ContentIcon.collection)
      }

      if series != nil {
        if canMarkSeriesAsRead {
          Button {
            markSeriesAsRead()
          } label: {
            Label("Mark as Read", systemImage: "checkmark")
          }
        }

        if canMarkSeriesAsUnread {
          Button {
            markSeriesAsUnread()
          } label: {
            Label("Mark as Unread", systemImage: "circle")
          }
        }
      }

      Divider()

      if current.isAdmin {
        Button(role: .destructive) {
          deferMenuActionPresentation { showDeleteConfirmation = true }
        } label: {
          Label("Delete Series", systemImage: "trash")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .toolbarButtonStyle()
  }

  private var readingProgressSummary: String? {
    guard let book = readingTargetBookForCurrentContext,
      let progress = book.readProgress,
      !progress.completed
    else { return nil }
    let page = progress.page
    guard book.media.pagesCount > 0 else { return "Page \(page)" }
    let value = min(max(Double(page) / Double(book.media.pagesCount), 0), 1)
    return "Page \(page) · \(value.formatted(.percent.precision(.fractionLength(0))))"
  }

  private var readingActionCaption: String {
    guard let readingProgressSummary else { return readLabel }
    return "\(readLabel) · \(readingProgressSummary)"
  }

  private var readingDisplayTitle: String {
    guard let book = readingTargetBookForCurrentContext else {
      return isResolvingReadingTarget ? String(localized: "Loading...") : navigationTitle
    }
    if book.oneshot || book.metadata.number.isEmpty {
      return book.metadata.title
    }
    return "#\(book.metadata.number) - \(book.metadata.title)"
  }

  /// Publishes the current continue-reading state to the shared context that
  /// backs the iOS 26 tab bar bottom accessory. On platforms and OS versions
  /// without the accessory this is a no-op.
  private func syncReadingBarContext() {
    // Never publish while the view is not on screen: the resolver's defer and
    // unstructured projection/refresh tasks can complete after the lifecycle
    // hooks cleared the context, and must not resurrect the accessory.
    guard isReadingBarVisible else { return }
    guard shouldShowReadingBar else {
      readingBarContext.clear(seriesId: seriesId)
      return
    }
    readingBarContext.present(
      ReadingActionBarContext.Presentation(
        seriesId: seriesId,
        instanceId: current.instanceId,
        bookId: readingTargetBookForCurrentContext?.id,
        caption: readingActionCaption,
        title: readingDisplayTitle,
        isResolving: isResolvingReadingTarget
      ),
      action: continueReading
    )
  }

  private func refreshReadingTargetBook(localOnly: Bool = false) async {
    readingTargetResolutionID += 1
    defer { syncReadingBarContext() }
    let resolutionID = readingTargetResolutionID
    let instanceId = current.instanceId
    let offline = isOffline

    if !isReadingTargetScoped(to: instanceId, isOffline: offline) {
      readingTargetBook = nil
    }
    readingTargetInstanceId = instanceId
    readingTargetIsOffline = offline

    guard canRead else {
      readingTargetBook = nil
      isResolvingReadingTarget = false
      return
    }

    // Prime from the local projection so the reading bar presents its final
    // content as the page appears; the server resolution below only corrects
    // it when the local projection is stale.
    if !offline {
      if readingTargetBookForCurrentContext == nil {
        let local = await SeriesContinueReadingResolver.resolveLocal(
          seriesId: seriesId, instanceId: instanceId)
        guard readingTargetResolutionID == resolutionID else { return }
        if readingTargetBookForCurrentContext == nil {
          updateReadingTarget(local, instanceId: instanceId, isOffline: offline)
        }
      }
      if localOnly {
        isResolvingReadingTarget = false
        return
      }
    }

    isResolvingReadingTarget = readingTargetBookForCurrentContext == nil
    let book = await resolveReadingTargetBook(instanceId: instanceId, isOffline: offline)
    guard readingTargetResolutionID == resolutionID else { return }
    guard instanceId == current.instanceId, offline == isOffline else { return }
    guard !Task.isCancelled else {
      isResolvingReadingTarget = false
      return
    }
    withAnimation(.appCurve(0.25)) {
      updateReadingTarget(book, instanceId: instanceId, isOffline: offline)
      isResolvingReadingTarget = false
    }
  }

  private func resolveReadingTargetBook(instanceId: String, isOffline: Bool) async -> Book? {
    guard canRead else { return nil }
    return await SeriesContinueReadingResolver.resolve(
      seriesId: seriesId,
      instanceId: instanceId,
      isOffline: isOffline
    )
  }

  private func updateReadingTarget(_ book: Book?, instanceId: String, isOffline: Bool) {
    readingTargetBook = book
    readingTargetInstanceId = instanceId
    readingTargetIsOffline = isOffline
  }

  private func clearReadingTargetForContextChange() {
    readingTargetResolutionID += 1
    readingTargetBook = nil
    readingTargetInstanceId = current.instanceId
    readingTargetIsOffline = isOffline
    isResolvingReadingTarget = false
    syncReadingBarContext()
  }

  private func isReadingTargetScoped(to instanceId: String, isOffline: Bool) -> Bool {
    readingTargetInstanceId == instanceId && readingTargetIsOffline == isOffline
  }

  private func shouldRefreshForBookProjection(_ notification: Notification) -> Bool {
    let changedIds = ContentProjectionNotifier.bookIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    if let readingTargetBook = readingTargetBookForCurrentContext,
      changedIds.contains(readingTargetBook.id)
    {
      return true
    }
    let visibleBookIds = Set(bookViewModel.pagination.items.map(\.id))
    guard !visibleBookIds.isEmpty else { return true }
    return !changedIds.isDisjoint(with: visibleBookIds)
  }

  private func shouldRefreshForSeriesProjection(_ notification: Notification) -> Bool {
    let changedIds = ContentProjectionNotifier.seriesIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    return changedIds.contains(seriesId)
  }
}
