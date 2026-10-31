//
// PanelModeController.swift
//
//

import CoreGraphics
import Foundation

/// Result of a `step`: either the controller handled it internally (zoomed within the
/// page) or the host must turn the page (the controller has recorded the direction so
/// the post-turn `updateCurrentPage` lands the cursor on the right whole-page bookend).
enum PanelStepOutcome: Equatable {
  case handled
  case turnPage(forward: Bool)
}

/// The brain of panel mode: owns the engaged state and a cursor over the current page's
/// `PanelSequence`, driving its `PanelZoomController`. It never calls back into the host;
/// the host reads `engaged`, calls `updateCurrentPage` / `engage` / `disengage` / `step`,
/// and performs page turns itself when `step` returns `.turnPage`.
///
/// Cursor is the N+2 array `[leading whole-page · panel[0…N-1] · trailing whole-page]`:
/// index 0 = leading whole-page, 1…N = panels, N+1 = trailing whole-page. The sequence is
/// already reading-ordered, so `step(forward:)` is direction-agnostic here.
@MainActor
@Observable
final class PanelModeController {
  /// Actively panel-walking — the host-facing `panelModeEngaged` signal that gates
  /// `.cover` pinning, the single-page invariant, and the zoom-guard carve-outs.
  private(set) var engaged = false

  /// True while the FIRST on-device detection runs long — in practice the one-time model compile that
  /// happens the first time panel mode is used after install. Lets the host show a brief "initialising"
  /// indicator. A fast first detection never flips this (the watchdog is cancelled before it fires).
  private(set) var isInitializing = false
  private var hasDetectedOnce = false
  private var initWatchdog: Task<Void, Never>?

  /// Owned here and exposed so the host can bind its `target` to the cover coordinator.
  let zoomController = PanelZoomController()

  private let orchestrator: PanelSequenceOrchestrator
  private var currentBookId: String?
  private var currentPage: BookPage?
  private var currentDirection: ReadingDirection = .ltr
  private var sequence: PanelSequence = .empty
  private var cursor = 0
  private var pendingTurnForward: Bool?

  init(
    provider: any PanelDetectionProvider = StubPanelProvider(),
    visionText: (any VisionTextProvider)? = VisionOCRTextProvider()
  ) {
    self.orchestrator = PanelSequenceOrchestrator(provider: provider, visionText: visionText)
  }

  /// Whether the current page can be engaged (double-tap walked). ANY non-empty sequence qualifies —
  /// not just panels: a `.splash` (a single panel, or a borderless body/near-splash crop) and a
  /// `.panels` walk built from orphan body beats or a text bubble-walk are all engageable. Only the
  /// `.empty` sequence (nothing to walk → whole page) stays armed. Named for engageability, not panels,
  /// so body/text-only pages are not mistaken for non-engageable.
  var isCurrentPageEngageable: Bool {
    switch sequence {
    case .panels(let rects): return !rects.isEmpty
    case .splash: return true
    case .empty: return false
    }
  }

  /// Called by the reader whenever the displayed page changes (armed or engaged).
  /// Eager-fetches the sequence; if a page turn is pending, lands the cursor on the
  /// whole-page bookend of the freshly turned-to page. `adjacentPages` are the
  /// same-segment neighbors to lazy-warm so a page turn lands on a ready sequence.
  func updateCurrentPage(
    bookId: String,
    page: BookPage,
    direction: ReadingDirection,
    adjacentPages: [BookPage] = []
  ) async {
    currentBookId = bookId
    currentPage = page
    currentDirection = direction

    // Eager-warm this page (`.userInitiated`) + lazy-warm neighbors (`.utility`), and
    // cancel detection that fell outside the new window. The `sequence` await below
    // reuses the in-flight current-page task (per-page dedup), so it is not computed twice.
    orchestrator.handlePageChange(
      bookId: bookId, currentPage: page, adjacentPages: adjacentPages, direction: direction)

    let resolved = await firstAwareSequence(bookId: bookId, page: page, direction: direction)

    // Drop a late result if the page changed again while awaiting.
    guard currentBookId == bookId, currentPage?.number == page.number else { return }
    sequence = resolved

    guard engaged, let forward = pendingTurnForward else { return }
    pendingTurnForward = nil
    // Land on the whole-page bookend (fit; completeTransition already reset zoom).
    cursor = forward ? 0 : max(sequence.count - 1, 0)
    zoomController.resetToFit(animated: false)
  }

  /// Double-tap engage at a normalized [0,1] page-space point (gutter → panel 0).
  /// No-ops only on a non-engageable (empty) page; if the sequence is not ready yet, waits briefly.
  func engage(atNormalizedPoint point: CGPoint?) {
    if isCurrentPageEngageable {
      performEngage(at: point)
      return
    }
    guard let bookId = currentBookId, let page = currentPage else { return }
    let direction = currentDirection
    Task { [weak self] in
      guard let self else { return }
      let resolved = await self.firstAwareSequence(
        bookId: bookId, page: page, direction: direction)
      guard self.currentBookId == bookId, self.currentPage?.number == page.number else { return }
      self.sequence = resolved
      guard self.isCurrentPageEngageable else { return }  // genuinely empty → stay armed
      self.performEngage(at: point)
    }
  }

  func disengage() {
    guard engaged else { return }
    engaged = false
    pendingTurnForward = nil
    cursor = 0
    zoomController.resetToFit(animated: true)
  }

  /// Panel mode fully turned off (not merely disengaged): exit engaged and cancel all
  /// in-flight detection so lazy-lookahead tasks do not outlive the mode.
  func deactivate() {
    disengage()
    orchestrator.cancelAll()
    initWatchdog?.cancel()
    isInitializing = false
  }

  /// Toggle engage/disengage at a point (the double-tap gesture).
  func toggleEngagement(atNormalizedPoint point: CGPoint?) {
    if engaged {
      disengage()
    } else {
      engage(atNormalizedPoint: point)
    }
  }

  @discardableResult
  func step(forward: Bool) -> PanelStepOutcome {
    guard engaged else { return .handled }
    let lastIndex = sequence.count - 1
    if lastIndex < 1 {
      pendingTurnForward = forward
      return .turnPage(forward: forward)
    }
    let next = forward ? cursor + 1 : cursor - 1
    // A splash's leading whole-page is a forward-only stop: you glance into the art once going
    // forward, but stepping backward off the splash turns the page rather than re-showing the
    // whole page (mirrors how a reader does a close look once, not again when paging back).
    if case .splash = sequence, !forward, next == 0 {
      pendingTurnForward = forward
      return .turnPage(forward: forward)
    }
    if next < 0 || next > lastIndex {
      pendingTurnForward = forward
      return .turnPage(forward: forward)
    }
    cursor = next
    zoomToCurrentCursor(animated: true)
    return .handled
  }

  // MARK: - Private

  /// Await a sequence, surfacing `isInitializing` only if the FIRST-ever detection runs past a short
  /// grace period (the one-time on-device model compile). Once any detection completes, later awaits
  /// skip the watchdog entirely.
  private func firstAwareSequence(
    bookId: String, page: BookPage, direction: ReadingDirection
  ) async -> PanelSequence {
    guard !hasDetectedOnce else {
      return await orchestrator.sequence(bookId: bookId, page: page, direction: direction)
    }
    initWatchdog?.cancel()
    initWatchdog = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.2))
      guard let self, !self.hasDetectedOnce, !Task.isCancelled else { return }
      self.isInitializing = true
    }
    let sequence = await orchestrator.sequence(bookId: bookId, page: page, direction: direction)
    initWatchdog?.cancel()
    hasDetectedOnce = true
    isInitializing = false
    return sequence
  }

  private func performEngage(at point: CGPoint?) {
    cursor = point.flatMap(panelArrayIndex(at:)) ?? 1
    engaged = true
    pendingTurnForward = nil
    zoomToCurrentCursor(animated: true)
  }

  private func zoomToCurrentCursor(animated: Bool) {
    if let rect = sequence[cursor] {
      zoomController.zoomToRect(rect, animated: animated)
    } else {
      zoomController.resetToFit(animated: animated)
    }
  }

  /// Walk-array index (1…N) of the panel containing `point`, or nil for a gutter / whole-page.
  private func panelArrayIndex(at point: CGPoint) -> Int? {
    func contains(_ rect: PanelRect) -> Bool {
      point.x >= rect.x && point.x <= rect.x + rect.width
        && point.y >= rect.y && point.y <= rect.y + rect.height
    }
    switch sequence {
    case .panels(let rects):
      for (index, rect) in rects.enumerated() where contains(rect) { return index + 1 }
      return nil
    case .splash(let rect):
      return contains(rect) ? 1 : nil
    case .empty:
      return nil
    }
  }
}
