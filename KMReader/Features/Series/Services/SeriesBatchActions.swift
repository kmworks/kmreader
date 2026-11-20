//
// SeriesBatchActions.swift
//
//

import Foundation

@MainActor
enum SeriesBatchActions {
  static func mark(
    ids: [String],
    read: Bool,
    using controller: BatchOperationController
  ) async -> BatchOperationOutcome {
    let outcome = await controller.run(ids: ids) { seriesId in
      if read {
        try await SeriesService.markAsRead(seriesId: seriesId)
      } else {
        try await SeriesService.markAsUnread(seriesId: seriesId)
      }
    }

    if !outcome.succeeded.isEmpty {
      await withTaskGroup(of: Void.self) { group in
        for seriesId in outcome.succeeded {
          group.addTask {
            _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
            try? await SyncService.syncAllSeriesBooks(seriesId: seriesId)
            await ContentProjectionNotifier.postSeriesBooksDidChange(
              seriesId: seriesId,
              reason: .readingProgress
            )
          }
        }
      }
      await DashboardSectionRefreshNotifier.postReadStatusChanged(
        source: .manual,
        reason: "Series read status changed"
      )
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alertBatchFailure(
        failedCount: outcome.failed.count,
        totalCount: outcome.totalCount,
        error: firstError
      )
    } else if read {
      ErrorManager.shared.notify(message: String(localized: "notification.series.markedRead"))
    } else {
      ErrorManager.shared.notify(message: String(localized: "notification.series.markedUnread"))
    }

    return outcome
  }

  static func deleteFiles(
    ids: [String],
    instanceId: String,
    using controller: BatchOperationController
  ) async -> BatchOperationOutcome {
    let outcome = await controller.run(ids: ids) { seriesId in
      try await SeriesDeletionService.deleteSeries(seriesId: seriesId, instanceId: instanceId)
    }

    if !outcome.succeeded.isEmpty {
      await DashboardSectionRefreshNotifier.postSeriesContentChanged(
        source: .manual,
        reason: "Series files batch deleted"
      )
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alertBatchFailure(
        failedCount: outcome.failed.count,
        totalCount: outcome.totalCount,
        error: firstError
      )
    } else {
      ErrorManager.shared.notify(
        message: String(localized: "batch.series.deleted \(outcome.succeeded.count)")
      )
    }

    return outcome
  }

  static func matchWithKomf(
    ids: [String],
    using controller: BatchOperationController
  ) async -> BatchOperationOutcome {
    let outcome = await controller.run(ids: ids) { seriesId in
      do {
        let series = try await SeriesService.getOneSeries(id: seriesId)
        try await KomfActions.submitMatch(
          libraryId: series.libraryId,
          seriesId: seriesId,
          seriesTitle: series.metadata.title
        )
      } catch {
        await KomfIntegrationStore.shared.handleConflictIfNeeded(error)
        throw error
      }
    }

    if let firstError = outcome.firstError {
      ErrorManager.shared.alertBatchFailure(
        failedCount: outcome.failed.count,
        totalCount: outcome.totalCount,
        error: firstError
      )
    } else {
      ErrorManager.shared.notify(
        message: String(localized: "batch.series.komfQueued \(outcome.succeeded.count)")
      )
    }

    return outcome
  }
}
