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
  private static let maxPollAttempts = 150

  private var tasks: [String: Task<Void, Never>] = [:]

  private init() {}

  func track(jobId: String, seriesId: String, seriesTitle: String) {
    guard tasks[jobId] == nil else { return }
    ErrorManager.shared.notify(
      message: String(localized: "komf job started for \(seriesTitle)"))
    tasks[jobId] = Task { [weak self] in
      guard let self else { return }
      await self.poll(jobId: jobId, seriesId: seriesId, seriesTitle: seriesTitle)
      self.tasks[jobId] = nil
    }
  }

  private func poll(jobId: String, seriesId: String, seriesTitle: String) async {
    for _ in 0..<Self.maxPollAttempts {
      try? await Task.sleep(nanoseconds: Self.pollInterval)
      if Task.isCancelled { return }
      do {
        let job = try await KomfService.getJob(id: jobId)
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
      }
    }
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
    _ = try? await SyncService.syncSeriesDetail(seriesId: seriesId)
    await ContentProjectionNotifier.postSeriesDidChange(seriesId: seriesId, reason: .content)
    await DashboardSectionRefreshNotifier.postSeriesContentChanged(
      source: .manual, reason: "komf metadata updated")
    ErrorManager.shared.notify(
      message: String(localized: "komf job completed for \(seriesTitle)"))
  }
}
