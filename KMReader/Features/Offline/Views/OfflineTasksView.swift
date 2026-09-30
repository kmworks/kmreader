//
// OfflineTasksView.swift
//
//

import SwiftUI

struct OfflineTasksView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  private var instanceId: String { current.instanceId }
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("offlinePaused") private var isPaused: Bool = false
  @State private var showingBulkAlert = false
  @State private var pendingBulkAction: BulkAction?
  @State private var tasks: [OfflineTaskItem] = []
  @State private var progressTracker = DownloadProgressTracker.shared

  private var coverSyncViewModel: OfflineCoverSyncViewModel {
    OfflineCoverSyncViewModel.shared
  }

  enum BulkAction {
    case retryAll, cancelAll
  }

  private var downloadingTasks: [OfflineTaskItem] {
    tasks.filter(\.isDownloading)
  }

  private var pendingTasks: [OfflineTaskItem] {
    tasks.filter(\.isPending)
  }

  private var failedTasks: [OfflineTaskItem] {
    tasks.filter(\.isFailed)
  }

  private var currentStatus: SyncStatus {
    if isPaused {
      return .paused
    }
    if !downloadingTasks.isEmpty {
      return .downloading
    }
    if !pendingTasks.isEmpty {
      return .syncing
    }
    return .idle
  }

  private var downloadsEnabledBinding: Binding<Bool> {
    Binding(
      get: { !isPaused },
      set: { setPaused(!$0) }
    )
  }

  var body: some View {
    Form {
      Section {
        Toggle(
          isOn: downloadsEnabledBinding
        ) {
          Label(currentStatus.label, systemImage: currentStatus.icon)
        }
      }

      OfflineCoverSyncSection(
        viewModel: coverSyncViewModel,
        instanceId: instanceId,
        isOffline: isOffline,
        defaultLibraryIds: dashboard.libraryIds
      )

      OfflineDataSyncSection(instanceId: instanceId, isOffline: isOffline)

      if !downloadingTasks.isEmpty {
        Section("Downloading") {
          ForEach(downloadingTasks) { task in
            OfflineTaskRow(
              task: task,
              onChanged: {
                Task {
                  await loadTasks()
                }
              }
            )
          }
        }
      }

      if !pendingTasks.isEmpty {
        Section("Pending") {
          ForEach(pendingTasks) { task in
            OfflineTaskRow(
              task: task,
              onChanged: {
                Task {
                  await loadTasks()
                }
              }
            )
          }
        }
      }

      if !failedTasks.isEmpty {
        Section {
          ForEach(failedTasks) { task in
            OfflineTaskRow(
              task: task,
              onChanged: {
                Task {
                  await loadTasks()
                }
              }
            )
          }
        } header: {
          HStack {
            Text("Failed")
            Spacer()
            HStack(spacing: 8) {
              Button {
                pendingBulkAction = .retryAll
                showingBulkAlert = true
              } label: {
                Text("Retry All")
                  .font(.caption)
              }
              .adaptiveButtonStyle(.bordered)
              .buttonBorderShape(.capsule)
              .optimizedControlSize()

              Button {
                pendingBulkAction = .cancelAll
                showingBulkAlert = true
              } label: {
                Text("Cancel All")
                  .font(.caption)
              }
              .adaptiveButtonStyle(.bordered)
              .tint(.red)
              .buttonBorderShape(.capsule)
              .optimizedControlSize()
            }
          }
        }
      }

      if tasks.isEmpty {
        ContentUnavailableView {
          Label("No Download Tasks", systemImage: "square.and.arrow.down")
        } description: {
          Text("No books are currently queued for offline reading.")
        }
        .tvFocusableHighlight()
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(OfflineSection.tasks.title)
    .alert(
      "Confirm Action", isPresented: $showingBulkAlert,
      presenting: pendingBulkAction
    ) { action in
      Button(role: .destructive) {
        Task {
          switch action {
          case .retryAll:
            await OfflineManager.shared.retryFailedDownloads(instanceId: instanceId)
            ErrorManager.shared.notify(
              message: String(localized: "notification.offline.retryAllFailed")
            )
            await loadTasks()
          case .cancelAll:
            await OfflineManager.shared.cancelFailedDownloads(instanceId: instanceId)
            ErrorManager.shared.notify(
              message: String(localized: "notification.offline.cancelAllFailed")
            )
            await loadTasks()
          }
        }
      } label: {
        Text(action == .retryAll ? "Retry All" : "Cancel All")
      }
      Button("Cancel", role: .cancel) {}
    } message: { action in
      Text(
        action == .retryAll
          ? "Are you sure you want to retry all failed downloads?"
          : "Are you sure you want to cancel all failed downloads?"
      )
    }
    .onChange(of: isPaused) { _, newValue in
      if newValue {
        // Pause: cancel all active background downloads
        #if os(iOS)
          BackgroundDownloadManager.shared.cancelAllDownloads()
        #endif
      } else {
        // Resume: trigger sync to restart downloads
        OfflineManager.shared.triggerSync(instanceId: instanceId, restart: true)
      }
    }
    .task(id: instanceId) {
      await loadTasks()
      OfflineManager.shared.triggerSync(instanceId: instanceId)
    }
    .onChange(of: progressTracker.queueUpdateToken) { _, _ in
      Task {
        await loadTasks()
      }
    }
  }

  private func loadTasks() async {
    guard !instanceId.isEmpty else {
      if !tasks.isEmpty {
        withAnimation {
          tasks = []
        }
      }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedTasks = try await database.fetchOfflineTaskItems(instanceId: instanceId)
      if tasks != loadedTasks {
        withAnimation {
          tasks = loadedTasks
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func setPaused(_ paused: Bool) {
    guard isPaused != paused else { return }
    withAnimation {
      isPaused = paused
    }
  }
}

struct OfflineTaskRow: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  private var instanceId: String { current.instanceId }
  let task: OfflineTaskItem
  let onChanged: () -> Void

  @State private var progressTracker = DownloadProgressTracker.shared

  private var progress: Double? {
    progressTracker.progress[task.bookId]
  }

  private var postDownloadStatusText: LocalizedStringResource {
    switch task.contentKind {
    case .archiveImages:
      "Validating offline archive..."
    case .epubWebPub, .epubDivina:
      "Finalizing offline EPUB..."
    case .pdf:
      "Finalizing offline PDF..."
    case .pages:
      "Finalizing offline pages..."
    }
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(task.seriesTitle)
          .font(.caption)
          .lineLimit(1)
        Text("#\(task.metaNumber) - \(task.metaTitle)")
          .lineLimit(1)

        if task.isPending || task.isDownloading, let progress = progress {
          if progress >= 1 {
            Text(postDownloadStatusText)
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ProgressView(value: progress) {
              Text("Downloading \(progress.formatted(.percent.precision(.fractionLength(0))))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        } else if case .failed(let error) = task.downloadStatus {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .lineLimit(2)
        }
      }

      Spacer()

      #if os(iOS) || os(macOS)
        HStack(spacing: 16) {
          if task.isFailed {
            Button {
              Task {
                await OfflineManager.shared.retryDownload(
                  instanceId: instanceId, bookId: task.bookId)
                onChanged()
              }
            } label: {
              Image(systemName: "arrow.clockwise.circle")
                .foregroundColor(.primary)
            }
            .adaptiveButtonStyle(.plain)
          }

          Button(role: .destructive) {
            Task {
              await OfflineManager.shared.cancelDownload(bookId: task.bookId)
              OfflineManager.shared.triggerSync(instanceId: instanceId)
              onChanged()
            }
          } label: {
            Image(systemName: task.isFailed ? "trash" : "xmark.circle")
              .foregroundColor(.red)
          }
          .adaptiveButtonStyle(.plain)
        }
      #endif
    }
    .padding(.vertical, 4)
  }
}
