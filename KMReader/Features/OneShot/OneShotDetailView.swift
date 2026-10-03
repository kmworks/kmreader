//
// OneShotDetailView.swift
//
//

import Flow
import SwiftUI

struct OneshotDetailView: View {
  let seriesId: String

  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var seriesItem: SeriesDisplayItem?
  @State private var loadedSeriesId: String?
  @State private var bookItem: BookDisplayItem?
  @State private var collections: [SidebarCollectionItem] = []
  @State private var readLists: [SidebarReadListItem] = []
  @State private var isLoading = true
  @State private var hasError = false
  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false
  @State private var showCollectionPicker = false
  @State private var showReadListPicker = false
  @State private var showKomfIdentify = false
  @State private var showKomfResetConfirmation = false

  init(seriesId: String) {
    self.seriesId = seriesId
  }

  private var series: Series? {
    seriesItem?.series
  }

  private var book: Book? {
    bookItem?.book
  }

  private var downloadStatus: DownloadStatus {
    bookItem?.downloadStatus ?? .notDownloaded
  }

  private var navigationTitle: String {
    book?.metadata.title ?? String(localized: "Oneshot")
  }

  private var shareURL: URL? {
    KomgaWebLinkBuilder.oneshot(serverURL: current.serverURL, seriesId: seriesId)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        if let book, let series {
          #if os(tvOS)
            oneshotToolbarContent
              .padding(.vertical, 8)
          #endif

          OneShotDetailContentView(
            book: book,
            series: series,
            downloadStatus: downloadStatus,
            protectionSources: bookItem?.protectionSources ?? [],
            inSheet: false
          )

          if seriesItem != nil {
            SeriesCollectionsSection(collections: collections)
          }

          if bookItem != nil {
            BookReadListsSection(readLists: readLists)
          }
        } else if hasError {
          VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
              .font(.largeTitle)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity)
        } else {
          VStack(spacing: 16) {
            ProgressView()
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding()
    }
    .platformNavigationTitle(navigationTitle)
    .komgaHandoff(
      title: navigationTitle,
      url: KomgaWebLinkBuilder.oneshot(serverURL: current.serverURL, seriesId: seriesId),
      scope: .browse
    )
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          oneshotToolbarContent
        }
      }
    #endif
    .alert("Delete Oneshot?", isPresented: $showDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        deleteOneshot()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete \(book?.metadata.title ?? "this oneshot") from Komga.")
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesId: seriesId,
        onSelect: { collectionId in
          addToCollection(collectionId: collectionId)
        }
      )
    }
    .sheet(isPresented: $showReadListPicker) {
      if let book = book {
        ReadListPickerSheet(
          bookId: book.id,
          onSelect: { readListId in
            addToReadList(readListId: readListId, bookId: book.id)
          }
        )
      }
    }
    .sheet(isPresented: $showEditSheet) {
      if let series = series, let book = book {
        OneshotEditSheet(series: series, book: book)
          .onDisappear {
            Task {
              await refreshOneshotData()
            }
          }
      }
    }
    .sheet(isPresented: $showKomfIdentify) {
      if let series {
        KomfIdentifySheet(series: series, book: book)
      }
    }
    .alert("Reset Metadata with komf?", isPresented: $showKomfResetConfirmation) {
      Button("Reset", role: .destructive) {
        resetWithKomf()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "komf removes the metadata it wrote for \(series?.metadata.title ?? "this oneshot"), including field locks and uploaded covers."
      )
    }
    .task {
      guard loadedSeriesId != seriesId else { return }
      loadedSeriesId = seriesId
      await KomfIntegrationStore.shared.refresh(isAdmin: current.isAdmin)
      await refreshOneshotData()
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) {
      notification in
      let changedIds = ContentProjectionNotifier.bookIds(from: notification)
      guard changedIds.isEmpty || changedIds.contains(book?.id ?? "") else { return }
      Task {
        await loadLocalOneshot()
      }
    }
  }

  private func refreshOneshotData() async {
    isLoading = true
    await loadLocalOneshot()
    do {
      _ = try await SyncService.syncSeriesDetail(seriesId: seriesId)
      let fetchedBooks = try await SyncService.syncBooks(
        seriesId: seriesId,
        page: 0,
        size: 1
      )
      isLoading = false
      await SyncService.syncSeriesCollections(seriesId: seriesId)
      if let fetchedBook = fetchedBooks.content.first {
        await SyncService.syncBookReadLists(bookId: fetchedBook.id)
      }
    } catch {
      if case APIError.notFound = error {
        dismiss()
      } else if seriesItem == nil || bookItem == nil {
        hasError = true
        ErrorManager.shared.alert(error: error)
      }
      isLoading = false
    }
    await loadLocalOneshot()
  }

  private func loadLocalOneshot() async {
    guard let database = try? await DatabaseOperator.database() else {
      seriesItem = nil
      bookItem = nil
      collections = []
      readLists = []
      return
    }

    seriesItem = try? await database.fetchSeriesDisplayItem(
      seriesId: seriesId,
      instanceId: current.instanceId
    )
    bookItem = try? await database.fetchFirstBookDisplayItem(
      seriesId: seriesId,
      instanceId: current.instanceId,
      includeOfflineProtection: true
    )
    await loadCollections()
    await loadReadLists()
  }

  private func loadCollections() async {
    let instanceId = current.instanceId
    guard let collectionIds = seriesItem?.collectionIds, !instanceId.isEmpty,
      !collectionIds.isEmpty
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

  private func loadReadLists() async {
    let instanceId = current.instanceId
    guard let readListIds = bookItem?.readListIds, !instanceId.isEmpty, !readListIds.isEmpty else {
      readLists = []
      return
    }
    do {
      let database = try await DatabaseOperator.database()
      let loadedReadLists = try await database.fetchSidebarReadLists(
        instanceId: instanceId,
        readListIds: Set(readListIds)
      )
      if readLists != loadedReadLists {
        withAnimation {
          readLists = loadedReadLists
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func clearCache() {
    guard let book = book else { return }
    Task {
      await CacheManager.clearCache(forBookId: book.id)
      ErrorManager.shared.notify(message: String(localized: "notification.book.cacheCleared"))
    }
  }

  private func addToCollection(collectionId: String) {
    Task {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: collectionId,
          seriesIds: [seriesId]
        )
        _ = try? await SyncService.syncCollection(id: collectionId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markOneshotAsRead() {
    guard let book = book else { return }
    Task {
      do {
        try await BookService.markAsRead(bookId: book.id)
        _ = try? await SyncService.syncBookAndSeries(bookId: book.id, seriesId: seriesId)
        await ContentProjectionNotifier.postBookAndSeriesDidChange(
          bookId: book.id,
          seriesId: seriesId,
          reason: .readingProgress
        )
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Book read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.markedRead"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markOneshotAsUnread() {
    guard let book = book else { return }
    Task {
      do {
        try await BookService.markAsUnread(bookId: book.id)
        _ = try? await SyncService.syncBookAndSeries(bookId: book.id, seriesId: seriesId)
        await ContentProjectionNotifier.postBookAndSeriesDidChange(
          bookId: book.id,
          seriesId: seriesId,
          reason: .readingProgress
        )
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Book read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.markedUnread"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deleteOneshot() {
    Task {
      do {
        if let series = seriesItem?.series {
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

  private func addToReadList(readListId: String, bookId: String) {
    Task {
      do {
        try await ReadListService.addBooksToReadList(
          readListId: readListId,
          bookIds: [bookId]
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func analyzeOneshot() {
    guard let book = book else { return }
    Task {
      do {
        try await BookService.analyzeBook(bookId: book.id)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.analysisStarted"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func refreshMetadata() {
    guard let book = book else { return }
    Task {
      do {
        try await BookService.refreshMetadata(bookId: book.id)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.metadataRefreshed"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func matchWithKomf() {
    guard let series else { return }
    Task {
      do {
        let response = try await KomfService.matchSeries(
          libraryId: series.libraryId, seriesId: series.id)
        await KomfJobTracker.shared.track(
          jobId: response.id,
          seriesId: series.id,
          seriesTitle: series.metadata.title.isEmpty ? series.name : series.metadata.title
        )
      } catch {
        if case APIError.httpError(let code, _, _, _, _) = error, code == 409 {
          await KomfIntegrationStore.shared.invalidate()
          await KomfIntegrationStore.shared.refresh(isAdmin: current.isAdmin)
        }
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func resetWithKomf() {
    guard let series else { return }
    Task {
      do {
        try await KomfService.resetSeries(libraryId: series.libraryId, seriesId: series.id)
        _ = try? await SyncService.syncSeriesDetail(seriesId: series.id)
        await ContentProjectionNotifier.postSeriesDidChange(
          seriesId: series.id, reason: .content)
        await DashboardSectionRefreshNotifier.postSeriesContentChanged(
          source: .manual, reason: "komf metadata reset")
        ErrorManager.shared.notify(
          message: String(localized: "komf metadata reset for \(series.metadata.title)"))
        await refreshOneshotData()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private var oneshotToolbarContent: some View {
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
          analyzeOneshot()
        } label: {
          Label("Analyze", systemImage: "waveform.path.ecg")
        }

        Button {
          refreshMetadata()
        } label: {
          Label("Refresh Metadata", systemImage: "arrow.clockwise")
        }

        #if os(iOS) || os(macOS)
          if KomfIntegrationStore.shared.isAvailable {
            Divider()

            Button {
              deferMenuActionPresentation { showKomfIdentify = true }
            } label: {
              Label("Identify with komf", systemImage: "sparkles")
            }

            Button {
              matchWithKomf()
            } label: {
              Label("Match with komf", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
              deferMenuActionPresentation { showKomfResetConfirmation = true }
            } label: {
              Label("Reset Metadata with komf", systemImage: "arrow.counterclockwise")
            }
          }
        #endif
      }

      Divider()

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

      Button {
        #if os(macOS)
          if let book {
            PickerWindowOpener.shared.open(.readList(bookId: book.id))
          }
        #else
          deferMenuActionPresentation { showReadListPicker = true }
        #endif
      } label: {
        Label("Add to Read List", systemImage: ContentIcon.readList)
      }

      Divider()

      if let book = book {
        if !book.isCompleted {
          Button {
            markOneshotAsRead()
          } label: {
            Label("Mark as Read", systemImage: "checkmark")
          }
        }

        if book.hasStartedReading {
          Button {
            markOneshotAsUnread()
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
          Label("Delete Oneshot", systemImage: "trash")
        }
      }

      if let book = book, book.isDivina {
        Button(role: .destructive) {
          clearCache()
        } label: {
          Label("Clear Cache", systemImage: "xmark")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .toolbarButtonStyle()
  }
}
