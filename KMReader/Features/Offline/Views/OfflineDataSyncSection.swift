//
// OfflineDataSyncSection.swift
//
//

import SwiftUI

struct OfflineDataSyncSection: View {
  let instanceId: String
  let isOffline: Bool

  @State private var showSyncConfirmation = false
  @State private var latestReadHistoryTime: Date?
  @State private var syncInfo: OfflineInstanceSyncInfo?

  private var syncViewModel: SyncViewModel {
    SyncViewModel.shared
  }

  private var lastSyncTimeText: String {
    guard let syncInfo else {
      return String(localized: "settings.sync_data.never")
    }
    if syncInfo.latestSync == Date(timeIntervalSince1970: 0) {
      return String(localized: "settings.sync_data.never")
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: syncInfo.latestSync, relativeTo: Date())
  }

  var body: some View {
    Section {
      Button {
        showSyncConfirmation = true
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(.secondary)
          Text(String(localized: "settings.sync_data"))
            .foregroundStyle(.primary)
          Spacer(minLength: 0)
          if syncViewModel.isSyncing {
            ProgressView()
          } else {
            Text(lastSyncTimeText)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(syncViewModel.isSyncing || isOffline || instanceId.isEmpty)

      Button {
        triggerReadingProgressSync()
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "book.circle")
            .foregroundStyle(.secondary)
          Text(String(localized: "offline.sync.confirm.progressOnlyAction"))
            .foregroundStyle(.primary)
          Spacer(minLength: 0)
          if let syncTime = latestReadHistoryTime {
            HStack(spacing: 4) {
              Text(String(localized: "offline.sync.readHistory.lastRead"))
              Text(syncTime.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          } else {
            Text(String(localized: "settings.sync_data.never"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isOffline || instanceId.isEmpty)
    } footer: {
      Text(String(localized: "settings.sync_data.description"))
    }
    .alert(
      String(localized: "offline.sync.confirm.title"),
      isPresented: $showSyncConfirmation
    ) {
      Button(String(localized: "offline.sync.confirm.action")) {
        Task {
          await syncViewModel.syncData()
          await loadSyncInfo()
        }
      }
      Button(String(localized: "offline.sync.confirm.forceAction"), role: .destructive) {
        Task {
          await syncViewModel.syncData(forceFullSync: true)
          await loadSyncInfo()
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(String(localized: "offline.sync.confirm.message"))
    }
    .task(id: instanceId) {
      latestReadHistoryTime = AppConfig.recentlyReadRecordTime(instanceId: instanceId)
      await loadSyncInfo()
    }
  }

  private func loadSyncInfo() async {
    guard !instanceId.isEmpty else {
      if syncInfo != nil { syncInfo = nil }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedSyncInfo = try await database.fetchOfflineInstanceSyncInfo(instanceId: instanceId)
      if syncInfo != loadedSyncInfo {
        syncInfo = loadedSyncInfo
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func triggerReadingProgressSync() {
    guard !isOffline, !instanceId.isEmpty else { return }

    Task(priority: .utility) {
      await syncViewModel.syncReadingProgressOnly(force: true)
      await MainActor.run {
        latestReadHistoryTime = AppConfig.recentlyReadRecordTime(instanceId: instanceId)
      }
    }
  }
}
