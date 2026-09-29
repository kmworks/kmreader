//
// OfflineBooksView.swift
//
//

import SwiftUI

struct OfflineBooksView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var showRemoveAllAlert = false
  @State private var showRemoveReadAlert = false
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
            countBadge(snapshot.totalDownloadedBooksCount)
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
              countBadge(lGroup.downloadedBooksCount)
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
                onDeleteBooks: deleteSeries
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
                onDeleteBooks: deleteSeries
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
    .alert(
      String(localized: "settings.offline_books.remove_all"),
      isPresented: $showRemoveAllAlert
    ) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Delete"), role: .destructive) {
        removeAllBooks()
      }
    } message: {
      Text(String(localized: "settings.offline_books.remove_all.message"))
    }
    .alert(
      String(localized: "settings.offline_books.remove_read"),
      isPresented: $showRemoveReadAlert
    ) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Delete"), role: .destructive) {
        removeReadBooks()
      }
    } message: {
      Text(String(localized: "settings.offline_books.remove_read.message"))
    }
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
      onRemoveRead: {
        showRemoveReadAlert = true
      },
      onCleanupOrphanedFiles: cleanupOrphanedFiles,
      onRemoveAll: {
        showRemoveAllAlert = true
      }
    )
  }

  private func countBadge(_ count: Int) -> some View {
    Text(count, format: .number)
      .font(.caption2)
      .fontWeight(.semibold)
      .monospacedDigit()
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.12), in: Capsule())
      .foregroundColor(.secondary)
      .lineLimit(1)
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
      await OfflineManager.shared.deleteBookManually(
        instanceId: book.instanceId, bookId: book.bookId)
      await loadSnapshot()
    }
  }

  private func deleteSeries(_ books: [OfflineDownloadedBookItem]) {
    guard let firstBook = books.first else { return }
    Task {
      await OfflineManager.shared.deleteBooksManually(
        seriesIds: Set(books.map(\.seriesId)),
        instanceId: firstBook.instanceId,
        bookIds: books.map { $0.bookId }
      )
      await loadSnapshot()
    }
  }

  private func removeAllBooks() {
    Task {
      await OfflineManager.shared.deleteAllDownloadedBooks()
      ErrorManager.shared.notify(
        message: String(localized: "notification.offline.booksRemovedAll")
      )
      await loadSnapshot()
    }
  }

  private func removeReadBooks() {
    Task {
      await OfflineManager.shared.deleteReadBooks()
      ErrorManager.shared.notify(
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
      if snapshot != loadedSnapshot {
        withAnimation {
          snapshot = loadedSnapshot
          snapshotReloadToken &+= 1
        }
      }
      if loadedSnapshot.hasReadBooks {
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
