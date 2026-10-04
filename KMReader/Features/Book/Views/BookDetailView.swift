//
// BookDetailView.swift
//
//

import Flow
import SwiftUI

struct BookDetailView: View {
  let bookId: String

  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var item: BookDisplayItem?
  @State private var loadedBookId: String?
  @State private var readLists: [SidebarReadListItem] = []
  @State private var hasError = false
  @State private var showDeleteConfirmation = false
  @State private var showReadListPicker = false
  @State private var showEditSheet = false

  init(bookId: String) {
    self.bookId = bookId
  }

  private var book: Book? {
    item?.book
  }

  private var downloadStatus: DownloadStatus {
    item?.downloadStatus ?? .notDownloaded
  }

  private var navigationTitle: String {
    book?.metadata.title ?? String(localized: "Book")
  }

  private var shareURL: URL? {
    KomgaWebLinkBuilder.book(serverURL: current.serverURL, bookId: bookId)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        if let book {
          #if os(tvOS)
            bookToolbarContent
              .padding(.vertical, 8)
          #endif

          BookDetailContentView(
            book: book,
            downloadStatus: downloadStatus,
            protectionSources: item?.protectionSources ?? [],
            inSheet: false
          )

          if item != nil {
            BookReadListsSection(readLists: readLists)
          }
        } else if hasError {
          ContentUnavailableView {
            Label("Failed to load book details", systemImage: "exclamationmark.triangle")
          } actions: {
            Button(String(localized: "Retry")) {
              Task {
                await loadBook()
              }
            }
            .adaptiveButtonStyle(.borderedProminent)
          }
          .frame(maxWidth: .infinity)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .padding()
    }
    .platformNavigationTitle(navigationTitle)
    .komgaHandoff(
      title: navigationTitle,
      url: KomgaWebLinkBuilder.book(serverURL: current.serverURL, bookId: bookId),
      scope: .browse
    )
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          bookToolbarContent
        }
      }
    #endif
    .alert("Delete Book?", isPresented: $showDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        deleteBook()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete \(book?.metadata.title ?? "this book") from Komga.")
    }
    .sheet(isPresented: $showReadListPicker) {
      ReadListPickerSheet(
        bookId: bookId,
        onSelect: { readListId in
          addToReadList(readListId: readListId)
        }
      )
    }
    .sheet(isPresented: $showEditSheet) {
      if let book = book {
        BookEditSheet(book: book)
          .onDisappear {
            Task {
              await loadBook()
            }
          }
      }
    }
    .task {
      guard loadedBookId != bookId else { return }
      loadedBookId = bookId
      await loadBook()
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) {
      notification in
      let changedIds = ContentProjectionNotifier.bookIds(from: notification)
      guard changedIds.isEmpty || changedIds.contains(bookId) else { return }
      Task {
        await loadLocalBook()
      }
    }
  }

  private func analyzeBook() {
    Task {
      do {
        try await BookService.analyzeBook(bookId: bookId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.analysisStarted"))
        await loadBook()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func refreshMetadata() {
    Task {
      do {
        try await BookService.refreshMetadata(bookId: bookId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.metadataRefreshed"))
        await loadBook()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deleteBook() {
    Task {
      do {
        if let book {
          try await BookDeletionService.deleteBook(book, instanceId: current.instanceId)
        } else {
          try await BookDeletionService.deleteBook(bookId: bookId, instanceId: current.instanceId)
        }
        ErrorManager.shared.notify(message: String(localized: "notification.book.deleted"))
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markBookAsRead() {
    Task {
      do {
        try await BookService.markAsRead(bookId: bookId)
        if let book {
          _ = try? await SyncService.syncBookAndSeries(
            bookId: bookId, seriesId: book.seriesId)
          await ContentProjectionNotifier.postBookAndSeriesDidChange(
            bookId: bookId,
            seriesId: book.seriesId,
            reason: .readingProgress
          )
        } else {
          await ContentProjectionNotifier.postBookDidChange(bookId: bookId, reason: .readingProgress)
        }
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Book read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.markedRead"))
        await loadBook()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markBookAsUnread() {
    Task {
      do {
        try await BookService.markAsUnread(bookId: bookId)
        if let book {
          _ = try? await SyncService.syncBookAndSeries(
            bookId: bookId,
            seriesId: book.seriesId
          )
          await ContentProjectionNotifier.postBookAndSeriesDidChange(
            bookId: bookId,
            seriesId: book.seriesId,
            reason: .readingProgress
          )
        } else {
          _ = try? await SyncService.syncBook(bookId: bookId)
          await ContentProjectionNotifier.postBookDidChange(bookId: bookId, reason: .readingProgress)
        }
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Book read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.markedUnread"))
        await loadBook()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func clearCache() {
    Task {
      await CacheManager.clearCache(forBookId: bookId)
      ErrorManager.shared.notify(message: String(localized: "notification.book.cacheCleared"))
    }
  }

  @MainActor
  private func loadBook() async {
    hasError = false
    await loadLocalBook()

    do {
      _ = try await SyncService.syncBook(bookId: bookId)
      await SyncService.syncBookReadLists(bookId: bookId)
    } catch {
      if case APIError.notFound = error {
        dismiss()
      } else {
        if item == nil {
          hasError = true
          ErrorManager.shared.alert(error: error)
        }
      }
    }
    await loadLocalBook()
  }

  private func loadLocalBook() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      readLists = []
      return
    }
    item = try? await database.fetchBookDisplayItem(
      bookId: bookId,
      instanceId: current.instanceId,
      includeOfflineProtection: true
    )
    await loadReadLists()
  }

  private func loadReadLists() async {
    let instanceId = current.instanceId
    guard let readListIds = item?.readListIds, !instanceId.isEmpty, !readListIds.isEmpty else {
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

  private func addToReadList(readListId: String) {
    Task {
      do {
        try await ReadListService.addBooksToReadList(
          readListId: readListId,
          bookIds: [bookId]
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        await loadBook()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private var bookToolbarContent: some View {
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
          analyzeBook()
        } label: {
          Label("Analyze", systemImage: "waveform.path.ecg")
        }

        Button {
          refreshMetadata()
        } label: {
          Label("Refresh Metadata", systemImage: "arrow.clockwise")
        }
      }

      Divider()

      Button {
        #if os(macOS)
          // Present in a standalone window: a view-attached sheet triggered
          // from an NSMenu action can wedge the app on macOS 15.
          PickerWindowOpener.shared.open(.readList(bookId: bookId))
        #else
          deferMenuActionPresentation { showReadListPicker = true }
        #endif
      } label: {
        Label("Add to Read List", systemImage: ContentIcon.readList)
      }

      if let book = book {
        if !book.isCompleted {
          Button {
            markBookAsRead()
          } label: {
            Label("Mark as Read", systemImage: "checkmark")
          }
        }

        if book.hasStartedReading {
          Button {
            markBookAsUnread()
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
          Label("Delete Book", systemImage: "trash")
        }
      }

      // Only show Clear Cache for non-EPUB books
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
