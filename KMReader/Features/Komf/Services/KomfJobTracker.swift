//
// KomfJobTracker.swift
//
//

import Foundation

/// Tracks komf jobs submitted from this app by polling, since only own jobs
/// matter here (kmweb uses the SSE firehose to also surface external jobs).
/// Server-side SSE events already refresh projections as komf writes metadata;
/// the completion sync below is the guarantee for when SSE is disabled.
@MainActor
final class KomfJobTracker {
  static let shared = KomfJobTracker()

  private static let pollInterval: UInt64 = 2_000_000_000
  private static let maxPollAttempts = 300
  private static let maxConsecutiveErrors = 5

  private var tasks: [String: Task<Void, Never>] = [:]

  private init() {}

  func track(jobId: String, seriesId: String, seriesTitle: String) {
    guard tasks[jobId] == nil else { return }
    let instanceId = AppConfig.current.instanceId
    ErrorManager.shared.notify(
      message: String(localized: "komf job started for \(seriesTitle)"))
    tasks[jobId] = Task { [weak self] in
      guard let self else { return }
      await self.poll(
        jobId: jobId, seriesId: seriesId, seriesTitle: seriesTitle, instanceId: instanceId)
      self.tasks[jobId] = nil
    }
  }

  private func poll(jobId: String, seriesId: String, seriesTitle: String, instanceId: String)
    async
  {
    var consecutiveErrors = 0
    for _ in 0..<Self.maxPollAttempts {
      try? await Task.sleep(nanoseconds: Self.pollInterval)
      if Task.isCancelled { return }
      // A server switch retargets getJob at the new instance, where the job id
      // is meaningless; stop silently instead of reporting a bogus failure.
      guard AppConfig.current.instanceId == instanceId else { return }
      do {
        let job = try await KomfService.getJob(id: jobId)
        consecutiveErrors = 0
        switch job.status {
        case .running:
          continue
        case .completed:
          await handleCompletion(seriesId: seriesId, seriesTitle: seriesTitle)
          return
        case .failed:
          notifyFailure(seriesTitle: seriesTitle, message: job.message)
          return
        }
      } catch {
        if case APIError.notFound = error {
          notifyFailure(seriesTitle: seriesTitle, message: nil)
          return
        }
        consecutiveErrors += 1
        if consecutiveErrors >= Self.maxConsecutiveErrors { return }
      }
    }
    // Timed out: the job may still be running server-side, so refresh whatever
    // metadata has landed and say tracking stopped.
    await refreshSeries(seriesId: seriesId)
    ErrorManager.shared.notify(
      message: String(localized: "komf job for \(seriesTitle) is taking longer than expected"))
  }

  private func notifyFailure(seriesTitle: String, message: String?) {
    let base = String(localized: "komf job failed for \(seriesTitle)")
    if let message, !message.isEmpty {
      ErrorManager.shared.notify(message: "\(base): \(message)", duration: 4)
    } else {
      ErrorManager.shared.notify(message: base, duration: 4)
    }
  }

  private func handleCompletion(seriesId: String, seriesTitle: String) async {
    await refreshSeries(seriesId: seriesId)
    ErrorManager.shared.notify(
      message: String(localized: "komf job completed for \(seriesTitle)"))
  }

  private func refreshSeries(seriesId: String) async {
    _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
    await ContentProjectionNotifier.postSeriesDidChange(seriesId: seriesId, reason: .content)
    await DashboardSectionRefreshNotifier.postSeriesContentChanged(
      source: .manual, reason: "komf metadata updated")
  }
}
