//
// BookContextMenu.swift
//
//

import SwiftUI

struct BookContextMenu: View {
  let book: Book
  let downloadStatus: DownloadStatus

  var onReadBook: ((Bool) -> Void)?
  var onShowReadListPicker: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil
  var onEditRequested: (() -> Void)? = nil
  var onMutationCompleted: (() -> Void)? = nil
  var showSeriesNavigation: Bool = true

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  var body: some View {
    Group {
      detailsSection

      if !isOffline {
        Button {
          deferMenuActionPresentation { onShowReadListPicker?() }
        } label: {
          Label("Add to Read List", systemImage: ContentIcon.readList)
        }
        if !book.isCompleted {
          Button {
            markAsRead(bookId: book.id)
          } label: {
            Label("Mark as Read", systemImage: AppIcon.markRead)
          }
        }
        if book.hasStartedReading {
          Button {
            markAsUnread(bookId: book.id)
          } label: {
            Label("Mark as Unread", systemImage: AppIcon.markUnread)
          }
        }
        Divider()

        if current.isAdmin {
          Menu {
            Button {
              deferMenuActionPresentation { onEditRequested?() }
            } label: {
              Label("Edit", systemImage: AppIcon.edit)
            }
            Button {
              analyzeBook(bookId: book.id)
            } label: {
              Label("Analyze", systemImage: AppIcon.analyze)
            }
            Button {
              refreshMetadata(bookId: book.id)
            } label: {
              Label("Refresh Metadata", systemImage: AppIcon.refresh)
            }

            if onDeleteRequested != nil {
              Divider()
              Button(role: .destructive) {
                deferMenuActionPresentation { onDeleteRequested?() }
              } label: {
                Label("Delete Book", systemImage: AppIcon.delete)
              }
            }
          } label: {
            Label("Manage", systemImage: AppIcon.settings)
          }

          Divider()
        }
      }

      Button {
        Task {
          let previousStatus = downloadStatus
          await OfflineManager.shared.toggleDownload(
            instanceId: current.instanceId, info: book.downloadInfo)
          // Removal and cancellation carry their own undo toasts; a plain one would
          // queue behind and report the outcome even when the user undoes.
          switch previousStatus {
          case .notDownloaded, .failed:
            ErrorManager.shared.notify(message: previousStatus.toggledNotification)
          case .downloaded, .pending:
            break
          }
          onMutationCompleted?()
        }
      } label: {
        Label(downloadStatus.menuLabel, systemImage: downloadStatus.menuIcon)
      }

      if !isOffline {
        Divider()
        Button {
          refreshCover()
        } label: {
          Label("Refresh Cover", systemImage: AppIcon.refresh)
        }
      }

      if book.isDivina {
        Divider()
        Button(role: .destructive) {
          Task {
            await CacheManager.clearCache(forBookId: book.id)
            ErrorManager.shared.notify(message: String(localized: "notification.book.cacheCleared"))
          }
        } label: {
          Label("Clear Cache", systemImage: AppIcon.clearCache)
        }
      }
    }
  }

  private func refreshCover() {
    Task {
      do {
        try await ThumbnailCache.refreshThumbnail(id: book.id, type: .book)
        ErrorManager.shared.notify(message: String(localized: "notification.book.coverRefreshed"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markAsRead(bookId: String) {
    Task {
      do {
        try await BookService.markAsRead(bookId: bookId)
        _ = try await SyncService.syncBookAndSeries(bookId: bookId, seriesId: book.seriesId)
        await ContentProjectionNotifier.postBookAndSeriesDidChange(
          bookId: bookId,
          seriesId: book.seriesId,
          reason: .readingProgress
        )
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Book read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.markedRead"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func markAsUnread(bookId: String) {
    Task {
      do {
        try await BookService.markAsUnread(bookId: bookId)
        _ = try await SyncService.syncBookAndSeries(bookId: bookId, seriesId: book.seriesId)
        await ContentProjectionNotifier.postBookAndSeriesDidChange(
          bookId: bookId,
          seriesId: book.seriesId,
          reason: .readingProgress
        )
        await DashboardSectionRefreshNotifier.postReadStatusChanged(
          source: .manual,
          reason: "Book read status changed"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.markedUnread"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func analyzeBook(bookId: String) {
    Task {
      do {
        try await BookService.analyzeBook(bookId: bookId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.analysisStarted"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func refreshMetadata(bookId: String) {
    Task {
      do {
        try await BookService.refreshMetadata(bookId: bookId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.metadataRefreshed"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private var detailsSection: some View {
    #if os(iOS)
      ControlGroup {
        NavigationLink(value: book.navDestination) {
          Label("Details", systemImage: AppIcon.details)
        }

        if let onReadBook = onReadBook {
          Button {
            onReadBook(true)
          } label: {
            Label("Peek", systemImage: AppIcon.peek)
          }
        }

        if showSeriesNavigation && !book.oneshot {
          NavigationLink(value: NavDestination.seriesDetail(seriesId: book.seriesId)) {
            Label("Series", systemImage: ContentIcon.series)
          }
        }
      }
    #else
      if let onReadBook = onReadBook {
        Button {
          onReadBook(true)
        } label: {
          Label("Peek", systemImage: AppIcon.peek)
        }
        Divider()
      }
      NavigationLink(value: book.navDestination) {
        Label("Details", systemImage: AppIcon.details)
      }
      if showSeriesNavigation && !book.oneshot {
        NavigationLink(value: NavDestination.seriesDetail(seriesId: book.seriesId)) {
          Label("Series", systemImage: ContentIcon.series)
        }
      }
      Divider()
    #endif
  }
}
