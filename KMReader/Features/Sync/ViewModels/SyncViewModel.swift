//
// SyncViewModel.swift
//
//

import Foundation

@MainActor
@Observable
final class SyncViewModel {
  static let shared = SyncViewModel()

  private(set) var isSyncing = false
  private var isSyncingReadingProgress = false
  private(set) var stageProgress = SyncStage.initialProgress
  private(set) var visibleStages = SyncStage.visibleStages(includeReconcile: false)
  private(set) var includesReconcileStages = false

  private let worker = SyncWorker()

  private init() {}

  func progress(for stage: SyncStage) -> Double {
    stageProgress[stage] ?? 0.0
  }

  func syncData(forceFullSync: Bool = false) async {
    guard !isSyncing, !isSyncingReadingProgress else { return }
    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else { return }

    isSyncing = true
    stageProgress = SyncStage.initialProgress
    includesReconcileStages = forceFullSync
    visibleStages = SyncStage.visibleStages(includeReconcile: forceFullSync)
    defer { isSyncing = false }

    let result = await worker.sync(
      request: SyncRequest(
        instanceId: instanceId,
        forceFullSync: forceFullSync
      )
    ) { [weak self] progress in
      self?.apply(progress)
    }

    if result.readingProgressSynced {
      AppConfig.setReadingProgressSyncTime(Date(), instanceId: instanceId)
    }
    await ReadListReadingService.shared.sync(instanceId: instanceId)

    ErrorManager.shared.notify(
      message: result.hasFailures
        ? String(localized: "notification.offline.syncCompletedWithIssues")
        : String(localized: "notification.offline.syncCompleted")
    )
  }

  /// Debounce for automatic reading-progress catch-up pulls (foreground
  /// activation, login, instance switch). Short enough that picking up a
  /// second device shows current progress, long enough to coalesce the rapid
  /// scene-phase cycles iOS emits (Control Center, app switcher, notification
  /// banners).
  private static let autoSyncMinimumInterval: TimeInterval = 30

  /// Pull recent cross-device reading progress when the app becomes active.
  /// Stays silent (no completion toast) since it is routine background
  /// freshness, not an explicit user-triggered sync.
  func syncReadingProgressOnForeground() async {
    await syncReadingProgressOnly(showsCompletionNotice: false)
  }

  func syncReadingProgressOnly(
    force: Bool = false,
    showsCompletionNotice: Bool = true
  ) async {
    guard !isSyncing, !isSyncingReadingProgress else { return }
    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else { return }
    guard force || !AppConfig.isOffline else { return }
    guard force || !shouldSkipReadingProgressSync(instanceId: instanceId) else { return }

    isSyncingReadingProgress = true
    defer { isSyncingReadingProgress = false }

    let syncSucceeded = await worker.syncReadingProgress(instanceId: instanceId)
    // Read list continuation is derived from reading progress, so reconcile the
    // read lists being read (and rebuild what they surface) after each pull.
    await ReadListReadingService.shared.sync(instanceId: instanceId)
    guard syncSucceeded else { return }

    AppConfig.setReadingProgressSyncTime(Date(), instanceId: instanceId)
    guard showsCompletionNotice else { return }
    ErrorManager.shared.notify(
      message: String(
        localized: "notification.offline.readHistorySyncCompleted",
        defaultValue: "Reading history sync completed"
      )
    )
  }

  private func shouldSkipReadingProgressSync(instanceId: String) -> Bool {
    guard let lastSyncTime = AppConfig.readingProgressSyncTime(instanceId: instanceId) else {
      return false
    }
    return Date().timeIntervalSince(lastSyncTime) < Self.autoSyncMinimumInterval
  }

  private func apply(_ syncProgress: SyncProgress) {
    let clampedProgress = min(max(syncProgress.phaseProgress, 0.0), 1.0)
    updateStageProgress(
      phase: syncProgress.phase,
      phaseProgress: clampedProgress,
      stage: syncProgress.stage
    )
  }

  private func updateStageProgress(
    phase: SyncPhase,
    phaseProgress: Double,
    stage: SyncStage?
  ) {
    switch phase {
    case .libraries:
      stageProgress[.libraries] = phaseProgress
    case .collections:
      stageProgress[.collections] = phaseProgress
    case .readLists:
      stageProgress[.readLists] = phaseProgress
    case .series:
      updateSplitStageProgress(
        incrementalStage: .seriesIncremental,
        reconcileStage: .seriesReconcile,
        phaseProgress: phaseProgress,
        stage: stage
      )
    case .books:
      updateSplitStageProgress(
        incrementalStage: .booksIncremental,
        reconcileStage: .booksReconcile,
        phaseProgress: phaseProgress,
        stage: stage
      )
    }
  }

  private func updateSplitStageProgress(
    incrementalStage: SyncStage,
    reconcileStage: SyncStage,
    phaseProgress: Double,
    stage: SyncStage?
  ) {
    guard includesReconcileStages else {
      stageProgress[incrementalStage] = phaseProgress
      stageProgress[reconcileStage] = 0.0
      return
    }

    if stage == incrementalStage {
      stageProgress[incrementalStage] = phaseProgress
    } else if stage == reconcileStage {
      stageProgress[reconcileStage] = phaseProgress
    }
  }
}
