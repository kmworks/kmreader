//
// SeriesContextMenu.swift
//
//

import SwiftUI

struct SeriesContextMenu: View {
  let seriesId: String
  let libraryId: String
  let seriesTitle: String
  let downloadStatus: SeriesDownloadStatus
  let offlinePolicy: OfflinePolicy
  let offlinePolicyLimit: Int
  let booksUnreadCount: Int
  let booksReadCount: Int
  let booksInProgressCount: Int

  var onShowCollectionPicker: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil
  var onEditRequested: (() -> Void)? = nil
  var onKomfIdentifyRequested: (() -> Void)? = nil
  var onMutationCompleted: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @Environment(\.readerActions) private var readerActions

  private var status: SeriesDownloadStatus {
    downloadStatus
  }

  private var canRead: Bool {
    booksUnreadCount + booksInProgressCount > 0
  }

  private var readLabel: String {
    if booksReadCount > 0 {
      return String(localized: "Resume Reading")
    } else {
      return String(localized: "Start Reading")
    }
  }

  private var canMarkAsRead: Bool {
    booksUnreadCount > 0
  }

  private var canMarkAsUnread: Bool {
    (booksReadCount + booksInProgressCount) > 0
  }

  private var limitPresets: [Int] {
    [1, 3, 5, 10, 25, 50, 0]
  }

  var body: some View {
    Group {
      if canRead {
        Button {
          continueReading()
        } label: {
          Label(readLabel, systemImage: "play")
        }
        Divider()
      }

      if !isOffline {
        Button {
          deferMenuActionPresentation { onShowCollectionPicker?() }
        } label: {
          Label("Add to Collection", systemImage: ContentIcon.collection)
        }

        if canMarkAsRead {
          Button {
            markSeriesAsRead()
          } label: {
            Label("Mark as Read", systemImage: "checkmark.circle")
          }
        }

        if canMarkAsUnread {
          Button {
            markSeriesAsUnread()
          } label: {
            Label("Mark as Unread", systemImage: "circle")
          }
        }

        Divider()

        if current.isAdmin {
          Menu {
            Button {
              deferMenuActionPresentation { onEditRequested?() }
            } label: {
              Label("Edit", systemImage: "pencil")
            }
            Button {
              analyzeSeries()
            } label: {
              Label("Analyze", systemImage: "waveform.path.ecg")
            }
            Button {
              refreshMetadata()
            } label: {
              Label("Refresh Metadata", systemImage: "arrow.clockwise")
            }

            if onDeleteRequested != nil {
              Divider()
              Button(role: .destructive) {
                deferMenuActionPresentation { onDeleteRequested?() }
              } label: {
                Label("Delete Series", systemImage: "trash")
              }
            }
          } label: {
            Label("Manage", systemImage: "gearshape")
          }

          #if os(iOS) || os(macOS)
            if KomfIntegrationStore.shared.isAvailable {
              KomfMenu(
                libraryId: libraryId,
                seriesId: seriesId,
                seriesTitle: seriesTitle,
                onIdentify: { onKomfIdentifyRequested?() }
              )
            }
          #endif

          Divider()
        }
      }

      Menu {
        Button {
          updatePolicy(.manual)
        } label: {
          offlinePolicyLabel(.manual)
        }

        Menu {
          ForEach(limitPresets, id: \.self) { value in
            Button {
              updatePolicyAndLimit(.unreadOnly, limit: value)
            } label: {
              limitOptionLabel(policy: .unreadOnly, limit: value)
            }
          }
        } label: {
          offlinePolicyLabel(.unreadOnly)
        }

        Button {
          updatePolicy(.all)
        } label: {
          offlinePolicyLabel(.all)
        }
      } label: {
        Label("Offline Policy", systemImage: offlinePolicy.icon)
      }

      Menu {
        actionsView(actions: SeriesDownloadAction.availableActions(for: status))
      } label: {
        Label("Download", systemImage: status.icon ?? "icloud.and.arrow.down")
      }

      if !isOffline {
        Divider()
        Button {
          refreshCover()
        } label: {
          Label("Refresh Cover", systemImage: "arrow.clockwise")
        }
      }
    }
  }

  private func refreshCover() {
    Task {
      do {
        try await ThumbnailCache.refreshThumbnail(id: seriesId, type: .series)
        ErrorManager.shared.notify(message: String(localized: "notification.series.coverRefreshed"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func continueReading() {
    Task {
      let book = await SeriesContinueReadingResolver.resolve(
        seriesId: seriesId,
        instanceId: current.instanceId,
        isOffline: isOffline
      )
      if let book {
        readerActions.open(book: book, incognito: false)
      }
    }
  }

  private func analyzeSeries() {
    Task {
      do {
        try await SeriesService.analyzeSeries(seriesId: seriesId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.analysisStarted"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func refreshMetadata() {
    Task {
      do {
        try await SeriesService.refreshMetadata(seriesId: seriesId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.metadataRefreshed"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
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
        onMutationCompleted?()
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
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func updatePolicy(_ policy: OfflinePolicy) {
    Task {
      // Sync books first if policy is not manual
      if policy != .manual {
        try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
      }
      try? await DatabaseOperator.database().updateSeriesOfflinePolicy(
        seriesId: seriesId, instanceId: current.instanceId, policy: policy
      )
      onMutationCompleted?()
    }
  }

  private func updatePolicyAndLimit(_ policy: OfflinePolicy, limit: Int) {
    Task {
      try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
      try? await DatabaseOperator.database().updateSeriesOfflinePolicy(
        seriesId: seriesId,
        instanceId: current.instanceId,
        policy: policy,
        limit: limit
      )
      onMutationCompleted?()
    }
  }

  @ViewBuilder
  private func actionsView(actions: [SeriesDownloadAction]) -> some View {
    ForEach(actions) { action in
      actionMenuItem(action: action)
    }
  }

  @ViewBuilder
  private func actionMenuItem(action: SeriesDownloadAction) -> some View {
    switch action {
    case .downloadUnread:
      Menu {
        downloadUnreadLimitOptions()
      } label: {
        Label(action.label(for: status), systemImage: action.icon(for: status))
      }
    default:
      Button(role: action.isDestructive ? .destructive : .none) {
        handleActionTap(action)
      } label: {
        Label(action.label(for: status), systemImage: action.icon(for: status))
      }
    }
  }

  private func handleActionTap(_ action: SeriesDownloadAction) {
    performAction(action)
  }

  private func handleDownloadUnreadTap(limit: Int) {
    downloadUnread(limit: limit)
  }

  @ViewBuilder
  private func offlinePolicyLabel(_ policy: OfflinePolicy) -> some View {
    let title = policy.title(limit: offlinePolicyLimit)
    Label {
      HStack(spacing: 4) {
        Text(policy == offlinePolicy ? title : policy.label)
        if policy == offlinePolicy {
          Image(systemName: "checkmark")
        }
      }
    } icon: {
      Image(systemName: policy.icon)
    }
  }

  @ViewBuilder
  private func downloadUnreadLimitOptions() -> some View {
    ForEach(limitPresets, id: \.self) { value in
      Button {
        handleDownloadUnreadTap(limit: value)
      } label: {
        Text(OfflinePolicy.limitTitle(value))
      }
    }
  }

  private func performAction(_ action: SeriesDownloadAction) {
    switch action {
    case .download:
      downloadAll()
    case .downloadUnread:
      downloadUnread(limit: offlinePolicyLimit)
    case .removeRead:
      removeRead()
    case .remove, .cancel:
      removeAll()
    }
  }

  private func downloadAll() {
    Task {
      try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
      try? await DatabaseOperator.database().downloadSeriesOffline(
        seriesId: seriesId, instanceId: current.instanceId
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.series.offlineDownloadQueued")
      )
      onMutationCompleted?()
    }
  }

  private func downloadUnread(limit: Int) {
    Task {
      try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
      try? await DatabaseOperator.database().downloadSeriesUnreadOffline(
        seriesId: seriesId,
        instanceId: current.instanceId,
        limit: limit
      )
      ErrorManager.shared.notify(
        message: String(localized: "notification.series.offlineDownloadQueued")
      )
      onMutationCompleted?()
    }
  }

  private func removeRead() {
    Task {
      await OfflineManager.shared.removeSeriesOfflineWithUndo(
        seriesId: seriesId, instanceId: current.instanceId, readOnly: true,
        message: String(localized: "notification.series.offlineRemoved")
      )
      onMutationCompleted?()
    }
  }

  private func removeAll() {
    Task {
      await OfflineManager.shared.removeSeriesOfflineWithUndo(
        seriesId: seriesId, instanceId: current.instanceId, readOnly: false,
        message: String(localized: "notification.series.offlineRemoved")
      )
      onMutationCompleted?()
    }
  }

  @ViewBuilder
  private func limitOptionLabel(policy: OfflinePolicy, limit: Int) -> some View {
    let title = OfflinePolicy.limitTitle(limit)
    if offlinePolicy == policy && offlinePolicyLimit == limit {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }

}
