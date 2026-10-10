//
// DashboardRefreshCoordinator.swift
//
//

import Foundation

@MainActor
final class DashboardRefreshCoordinator {
  static let shared = DashboardRefreshCoordinator()

  private let debounceInterval: TimeInterval = 5.0
  private let logger = AppLogger(.dashboard)

  private var isAutoRefreshEnabled = AppConfig.enableSSEAutoRefresh
  private var activeReaderSessionID: UUID?
  private var pendingAutoRefreshTask: Task<Void, Never>?
  private var pendingAutoSections: Set<DashboardSection>?
  private var hasDeferredAutoRefresh = false
  private var deferredAutoSections: Set<DashboardSection>?
  private var hasDeferredProjectionRefresh = false
  private var deferredProjectionSections: Set<DashboardSection>?
  private var projectionObserverTasks: [Task<Void, Never>] = []

  private init() {
    startProjectionObservers()
  }

  func configure(autoRefreshEnabled: Bool) {
    setAutoRefreshEnabled(autoRefreshEnabled)
  }

  func setAutoRefreshEnabled(_ isEnabled: Bool) {
    isAutoRefreshEnabled = isEnabled
    guard !isEnabled else { return }

    cancelPendingAutoRefresh(clearDeferred: true)
  }

  func readerDidOpen(sessionID: UUID) {
    activeReaderSessionID = sessionID
    movePendingAutoRefreshToDeferred()
  }

  func readerDidClose(sessionID: UUID) {
    guard activeReaderSessionID == sessionID else { return }
    activeReaderSessionID = nil
    flushDeferredProjectionRefresh()
    flushDeferredAutoRefresh()
  }

  func cancelPendingAutoRefresh(clearDeferred: Bool = false) {
    pendingAutoRefreshTask?.cancel()
    pendingAutoRefreshTask = nil
    pendingAutoSections = nil

    if clearDeferred {
      hasDeferredAutoRefresh = false
      deferredAutoSections = nil
    }
  }

  func requestRefresh(
    sections: Set<DashboardSection>?,
    source: DashboardRefreshSource,
    reason: String
  ) async {
    switch source {
    case .manual:
      requestManualRefresh(sections: sections, reason: reason)
    case .auto:
      scheduleAutoRefresh(sections: sections, reason: reason)
    case .projection:
      requestProjectionRefresh(sections: sections, reason: reason)
    }
  }

  /// Manual refreshes go straight to the dashboard: it observes the reload
  /// notification once and awaits its view model, so no per-section
  /// acknowledgement is needed.
  private func requestManualRefresh(
    sections: Set<DashboardSection>?,
    reason: String
  ) {
    logger.debug("Dashboard manual refresh requested: \(reason)")

    if sections == nil {
      cancelPendingAutoRefresh(clearDeferred: true)
    }

    DashboardSectionRefreshNotifier.postReload(
      command: DashboardSectionReloadCommand(
        id: UUID(),
        source: .manual,
        sections: sections,
        reason: reason
      )
    )
  }

  private func requestProjectionRefresh(
    sections: Set<DashboardSection>?,
    reason: String
  ) {
    logger.debug("Dashboard projection refresh requested: \(reason)")

    if activeReaderSessionID != nil {
      mergeDeferredProjectionSections(sections)
      return
    }

    DashboardSectionRefreshNotifier.postReload(
      command: DashboardSectionReloadCommand(
        id: UUID(),
        source: .projection,
        sections: sections,
        reason: reason
      )
    )
  }

  private func scheduleAutoRefresh(
    sections: Set<DashboardSection>?,
    reason: String,
    delay: TimeInterval? = nil
  ) {
    guard isAutoRefreshEnabled else { return }

    logger.debug("Dashboard auto refresh scheduled: \(reason)")

    if activeReaderSessionID != nil {
      mergeDeferredAutoSections(sections)
      return
    }

    mergePendingAutoSections(sections)

    pendingAutoRefreshTask?.cancel()
    let refreshDelay = delay ?? debounceInterval
    pendingAutoRefreshTask = Task { @MainActor in
      if refreshDelay > 0 {
        do {
          try await Task.sleep(nanoseconds: UInt64(refreshDelay * 1_000_000_000))
        } catch {
          return
        }
      } else {
        await Task.yield()
      }

      guard !Task.isCancelled else { return }
      finishPendingAutoRefresh(reason: reason, refreshDelay: refreshDelay)
    }
  }

  private func finishPendingAutoRefresh(reason: String, refreshDelay: TimeInterval) {
    let sections = pendingAutoSections
    pendingAutoRefreshTask = nil
    pendingAutoSections = nil

    if activeReaderSessionID != nil {
      mergeDeferredAutoSections(sections)
      return
    }

    let refreshReason =
      refreshDelay > 0 ? "Auto after debounce: \(reason)" : "Auto immediately: \(reason)"
    logger.debug("Dashboard auto refresh executing: \(refreshReason)")
    DashboardSectionRefreshNotifier.postReload(
      command: DashboardSectionReloadCommand(
        id: UUID(),
        source: .auto,
        sections: sections,
        reason: refreshReason
      )
    )
  }

  private func mergePendingAutoSections(_ sections: Set<DashboardSection>?) {
    if pendingAutoRefreshTask != nil, pendingAutoSections == nil {
      return
    }
    guard let sections else {
      pendingAutoSections = nil
      return
    }
    if let existingSections = pendingAutoSections {
      pendingAutoSections = existingSections.union(sections)
    } else {
      pendingAutoSections = sections
    }
  }

  private func mergeDeferredAutoSections(_ sections: Set<DashboardSection>?) {
    if hasDeferredAutoRefresh, deferredAutoSections == nil {
      return
    }
    hasDeferredAutoRefresh = true
    guard let sections else {
      deferredAutoSections = nil
      return
    }
    if let existingSections = deferredAutoSections {
      deferredAutoSections = existingSections.union(sections)
    } else {
      deferredAutoSections = sections
    }
  }

  private func mergeDeferredProjectionSections(_ sections: Set<DashboardSection>?) {
    if hasDeferredProjectionRefresh, deferredProjectionSections == nil {
      return
    }
    hasDeferredProjectionRefresh = true
    guard let sections else {
      deferredProjectionSections = nil
      return
    }
    if let existingSections = deferredProjectionSections {
      deferredProjectionSections = existingSections.union(sections)
    } else {
      deferredProjectionSections = sections
    }
  }

  private func movePendingAutoRefreshToDeferred() {
    guard pendingAutoRefreshTask != nil else { return }
    mergeDeferredAutoSections(pendingAutoSections)
    cancelPendingAutoRefresh()
  }

  private func flushDeferredAutoRefresh() {
    guard hasDeferredAutoRefresh else { return }
    let sections = deferredAutoSections
    hasDeferredAutoRefresh = false
    deferredAutoSections = nil
    scheduleAutoRefresh(
      sections: sections,
      reason: "Reader closed after deferred dashboard refresh",
      delay: 0
    )
  }

  private func flushDeferredProjectionRefresh() {
    guard hasDeferredProjectionRefresh else { return }
    let sections = deferredProjectionSections
    hasDeferredProjectionRefresh = false
    deferredProjectionSections = nil

    DashboardSectionRefreshNotifier.postReload(
      command: DashboardSectionReloadCommand(
        id: UUID(),
        source: .projection,
        sections: sections,
        reason: "Reader closed after deferred dashboard projection refresh"
      )
    )
  }

  private func startProjectionObservers() {
    observeBookProjection()
    observeSeriesProjection()
  }

  private func observeBookProjection() {
    projectionObserverTasks.append(
      Task { @MainActor [weak self] in
        for await notification in NotificationCenter.default.notifications(named: .bookProjectionDidChange) {
          let reasons = ContentProjectionNotifier.changeReasons(from: notification)
          let sections = DashboardSectionRefreshNotifier.sectionsForBookProjectionChange(reasons: reasons)
          guard !sections.isEmpty else { continue }
          await self?.requestRefresh(sections: sections, source: .projection, reason: "Book projection changed")
        }
      }
    )
  }

  private func observeSeriesProjection() {
    projectionObserverTasks.append(
      Task { @MainActor [weak self] in
        for await notification in NotificationCenter.default.notifications(named: .seriesProjectionDidChange) {
          let reasons = ContentProjectionNotifier.changeReasons(from: notification)
          let sections = DashboardSectionRefreshNotifier.sectionsForSeriesProjectionChange(reasons: reasons)
          guard !sections.isEmpty else { continue }
          await self?.requestRefresh(sections: sections, source: .projection, reason: "Series projection changed")
        }
      }
    )
  }
}
