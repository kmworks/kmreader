//
// KomfActions.swift
//
//

import Foundation

/// Shared komf menu commands so detail pages and context menus don't diverge.
nonisolated enum KomfActions {
  static func match(libraryId: String, seriesId: String, seriesTitle: String) async {
    do {
      let response = try await KomfService.matchSeries(
        libraryId: libraryId, seriesId: seriesId)
      await KomfJobTracker.shared.track(
        jobId: response.id,
        seriesId: seriesId,
        seriesTitle: seriesTitle
      )
    } catch {
      await KomfIntegrationStore.shared.handleConflictIfNeeded(error)
      await ErrorManager.shared.alert(error: error)
    }
  }

  static func reset(libraryId: String, seriesId: String, seriesTitle: String) async {
    do {
      try await KomfService.resetSeries(libraryId: libraryId, seriesId: seriesId)
      _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
      await ContentProjectionNotifier.postSeriesDidChange(
        seriesId: seriesId, reason: .content)
      await DashboardSectionRefreshNotifier.postSeriesContentChanged(
        source: .manual, reason: "komf metadata reset")
      await ErrorManager.shared.notify(
        message: String(localized: "komf metadata reset for \(seriesTitle)"))
    } catch {
      await KomfIntegrationStore.shared.handleConflictIfNeeded(error)
      await ErrorManager.shared.alert(error: error)
    }
  }
}
