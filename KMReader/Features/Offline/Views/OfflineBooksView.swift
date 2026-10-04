//
// OfflineBooksView.swift
//
//

import SwiftUI

struct OfflineBooksView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var isScanning = false
  @State private var snapshot: OfflineDownloadedBooksSnapshot = .empty
  @State private var snapshotReloadToken = 0
  @State private var canRemoveReadBooks = false
  @State private var progressTracker = DownloadProgressTracker.shared

  private let formatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = .useAll
    f.countStyle = .file
    return f
  }()

  var body: some View {
    Form {
      if snapshot.isEmpty {
        ContentUnavailableView {
          Label(String(localized: "settings.offline.no_books"), systemImage: ContentIcon.book)
        } description: {
          Text(String(localized: "settings.offline.no_books.description"))
        }
        .tvFocusableHighlight()
      } else {
        Section {
          HStack {
            Text(String(localized: "settings.offline_books.total"))
              .fontWeight(.semibold)
            OfflineCountBadge(count: snapshot.totalDownloadedBooksCount)
            Spacer()
            totalMetrics(size: snapshot.totalDownloadedSize)
          }
        }

        #if os(tvOS)
          Section {
            managementMenu
              .adaptiveButtonStyle(.bordered)
          }
        #endif

        ForEach(snapshot.libraryGroups) { lGroup in
          Section(
            header: HStack {
              Text(lGroup.name ?? String(localized: "Unknown"))
              OfflineCountBadge(count: lGroup.downloadedBooksCount)
              Spacer()
              downloadedMetrics(size: lGroup.downloadedSize)
            }
          ) {
            ForEach(lGroup.seriesGroups) { sGroup in
              OfflineDownloadedBookGroupView(
                groupId: "series:\(sGroup.id)",
                title: sGroup.name ?? String(localized: "Unknown"),
                books: sGroup.books,
                titleStyle: .numbered,
                reloadToken: snapshotReloadToken,
                onDeleteBook: deleteBook,
                onDeleteBooks: deleteSeriesBooks
              )
            }

            if !lGroup.oneshotBooks.isEmpty {
              OfflineDownloadedBookGroupView(
                groupId: "oneshot:\(lGroup.id)",
                title: String(localized: "settings.offline_books.oneshots"),
                books: lGroup.oneshotBooks,
                titleStyle: .oneshot,
                reloadToken: snapshotReloadToken,
                onDeleteBook: deleteBook,
                onDeleteBooks: deleteOneshotBooks
              )
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(OfflineSection.books.title)
    #if os(iOS) || os(macOS)
      .toolbar {
        if !snapshot.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            managementMenu
          }
        }
      }
    #endif
    .task(id: current.instanceId) {
      await loadSnapshot()
    }
    .onChange(of: progressTracker.queueUpdateToken) { _, _ in
      Task {
        await loadSnapshot()
      }
    }
  }

  private var managementMenu: some View {
    OfflineBooksManagementMenu(
      canRemoveReadBooks: canRemoveReadBooks,
      isScanning: isScanning,
      onRemoveRead: removeReadBooks,
      onCleanupOrphanedFiles: cleanupOrphanedFiles,
      onRemoveAll: removeAllBooks
    )
  }

  private func totalMetrics(size: Int64) -> some View {
    Text(formatter.string(fromByteCount: size))
      .foregroundColor(.secondary)
      .lineLimit(1)
  }

  private func downloadedMetrics(size: Int64) -> some View {
    Text(formatter.string(fromByteCount: size))
      .font(.caption)
      .foregroundColor(.secondary)
      .lineLimit(1)
  }

  private func deleteBook(_ book: OfflineDownloadedBookItem) {
    Task {
      await OfflineManager.shared.deleteBooksWithUndo(
        seriesIds: [book.seriesId],
        instanceId: book.instanceId,
        bookIds: [book.bookId],
        message: String(localized: "notification.book.offlineRemoved")
      )
      await loadSnapshot()
    }
  }

  private func deleteSeriesBooks(_ books: [OfflineDownloadedBookItem]) {
    deleteBookGroup(books, message: String(localized: "notification.series.offlineRemoved"))
  }

  private func deleteOneshotBooks(_ books: [OfflineDownloadedBookItem]) {
    deleteBookGroup(books, message: String(localized: "notification.book.offlineRemoved"))
  }

  private func deleteBookGroup(_ books: [OfflineDownloadedBookItem], message: String) {
    guard let firstBook = books.first else { return }
    Task {
      await OfflineManager.shared.deleteBooksWithUndo(
        seriesIds: Set(books.map(\.seriesId)),
        instanceId: firstBook.instanceId,
        bookIds: books.map { $0.bookId },
        message: message
      )
      await loadSnapshot()
    }
  }

  private func removeAllBooks() {
    Task {
      await OfflineManager.shared.deleteAllDownloadedBooksWithUndo(
        message: String(localized: "notification.offline.booksRemovedAll")
      )
      await loadSnapshot()
    }
  }

  private func removeReadBooks() {
    Task {
      await OfflineManager.shared.deleteReadBooksWithUndo(
        message: String(localized: "notification.offline.booksRemovedRead")
      )
      await loadSnapshot()
    }
  }

  private func cleanupOrphanedFiles() {
    Task {
      isScanning = true
      let result = await OfflineManager.shared.cleanupOrphanedFiles()
      isScanning = false
      if result.deletedCount > 0 {
        ErrorManager.shared.notify(
          message: String(
            localized:
              "settings.offline_books.cleanup_orphaned.result \(result.deletedCount) \(formatter.string(fromByteCount: result.bytesFreed))"
          )
        )
      } else {
        ErrorManager.shared.notify(
          message: String(localized: "settings.offline_books.cleanup_orphaned.no_orphaned")
        )
      }
      await loadSnapshot()
    }
  }

  private func loadSnapshot() async {
    let instanceId = current.instanceId
    guard !instanceId.isEmpty else {
      canRemoveReadBooks = false
      if snapshot != .empty {
        withAnimation {
          snapshot = .empty
          snapshotReloadToken &+= 1
        }
      }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedSnapshot = try await database.fetchOfflineDownloadedBooksSnapshot(
        instanceId: instanceId
      )
      let pendingBookIds = await OfflineManager.shared.pendingDeletionBookIds(
        instanceId: instanceId)
      let visibleSnapshot = loadedSnapshot.filtered(excludingBookIds: pendingBookIds)
      if snapshot != visibleSnapshot {
        withAnimation {
          snapshot = visibleSnapshot
          snapshotReloadToken &+= 1
        }
      }
      if visibleSnapshot.hasReadBooks {
        await loadReadRemovalAvailability(instanceId: instanceId)
      } else {
        canRemoveReadBooks = false
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadReadRemovalAvailability(instanceId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      let canRemove = await database.hasReadBooksEligibleForAutoDelete(instanceId: instanceId)
      guard current.instanceId == instanceId else { return }
      if canRemoveReadBooks != canRemove {
        canRemoveReadBooks = canRemove
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
