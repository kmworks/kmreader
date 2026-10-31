//
// PanelSequenceOrchestrator.swift
//
//

import CoreGraphics
import Foundation

/// Drives panel detection lazily, cancellably, and stale-safely, writing results into
/// a `PanelSequenceCache`. Eager for the current page (the engage precondition), lazy
/// lookahead for neighbors, cancellable on page flip and mode exit.
///
/// Concurrency contract: a cancelled `detect` resolves to `.empty`, indistinguishable
/// from a genuine "no panels" result — so a cancelled/superseded task's result is
/// **never** written to the cache (that would poison the page with a false `.empty`).
@MainActor
final class PanelSequenceOrchestrator {
  private struct PageToken: Hashable {
    let bookId: String
    let pageNumber: Int
  }

  private struct InFlight {
    let id: Int
    let task: Task<PanelSequence, Never>
  }

  private let provider: any PanelDetectionProvider
  /// Optional OCR text-line source for the readability paths; nil disables them entirely.
  private let visionText: (any VisionTextProvider)?
  private let cache: PanelSequenceCache
  /// Per-book OCR-route memory: once a book is known vertical/CJK, OCR is skipped (it is blind there).
  private let scriptCache: PanelTextScriptCache
  private let loader: any PanelImageLoading
  private let logger = AppLogger(.reader)  // DEBUG: ordering diagnostics; strip before fold

  private var inFlight: [PageToken: InFlight] = [:]
  private var nextRequestId = 0

  init(
    provider: any PanelDetectionProvider,
    visionText: (any VisionTextProvider)? = nil,
    cache: PanelSequenceCache = PanelSequenceCache(),
    scriptCache: PanelTextScriptCache = PanelTextScriptCache(),
    loader: any PanelImageLoading = PanelPageImageLoader()
  ) {
    self.provider = provider
    self.visionText = visionText
    self.cache = cache
    self.scriptCache = scriptCache
    self.loader = loader
  }

  /// In-flight detection count — diagnostics / debug harness only.
  var inFlightCount: Int { inFlight.count }

  /// Cache hit, else eager compute (awaited). The precondition for engage.
  func sequence(bookId: String, page: BookPage, presentation: PanelPagePresentation) async -> PanelSequence {
    let key = makeKey(bookId: bookId, page: page, presentation: presentation)
    if let cached = await cache.sequence(for: key.fingerprint) { return cached }
    return await task(for: bookId, page: page, presentation: presentation, priority: .userInitiated).value
  }

  /// Kick off detection without awaiting (lazy lookahead / pre-warm).
  func prewarm(bookId: String, page: BookPage, presentation: PanelPagePresentation, priority: TaskPriority = .utility) {
    _ = task(for: bookId, page: page, presentation: presentation, priority: priority)
  }

  /// Eager-warm the current page and lazy-warm its neighbors; cancel anything that
  /// fell outside the new window (different book or page no longer adjacent).
  func handlePageChange(
    bookId: String,
    currentPage: BookPage,
    adjacentPages: [BookPage],
    presentation: PanelPagePresentation
  ) {
    let window = Set([currentPage.number] + adjacentPages.map(\.number))
    for (token, entry) in inFlight where token.bookId != bookId || !window.contains(token.pageNumber) {
      entry.task.cancel()
      inFlight[token] = nil
    }

    prewarm(bookId: bookId, page: currentPage, presentation: presentation, priority: .userInitiated)
    for page in adjacentPages {
      prewarm(bookId: bookId, page: page, presentation: presentation, priority: .utility)
    }
  }

  /// Cancel and forget every in-flight detection (mode exit).
  func cancelAll() {
    for entry in inFlight.values { entry.task.cancel() }
    inFlight.removeAll()
  }

  // MARK: - Private

  /// The single in-flight task per page — de-duplicates concurrent requests.
  private func task(
    for bookId: String,
    page: BookPage,
    presentation: PanelPagePresentation,
    priority: TaskPriority
  ) -> Task<PanelSequence, Never> {
    let token = PageToken(bookId: bookId, pageNumber: page.number)
    if let existing = inFlight[token] { return existing.task }

    nextRequestId += 1
    let id = nextRequestId
    let work = Task(priority: priority) { [weak self] () -> PanelSequence in
      guard let self else { return .empty }
      let result = await self.compute(bookId: bookId, page: page, presentation: presentation)
      self.clearSlot(token: token, id: id)
      return result
    }
    inFlight[token] = InFlight(id: id, task: work)
    return work
  }

  /// Clear the in-flight slot only if it is still the task we created (not a newer one).
  private func clearSlot(token: PageToken, id: Int) {
    if inFlight[token]?.id == id { inFlight[token] = nil }
  }

  private func compute(bookId: String, page: BookPage, presentation: PanelPagePresentation) async -> PanelSequence {
    let key = makeKey(bookId: bookId, page: page, presentation: presentation)
    if let cached = await cache.sequence(for: key.fingerprint) { return cached }

    guard let image = await loader.pageImage(bookId: bookId, page: page) else {
      // Transient load failure → show whole, but do NOT cache (retry next time).
      return .empty
    }

    let detection = await provider.detect(image: image)

    // Drop a cancelled/superseded result: a cancelled detect resolves to `.empty`,
    // which must never be cached as a genuine "no panels".
    guard !Task.isCancelled else { return .empty }

    // Detector-agnostic pruning of phantom panels (blank slivers / spread seams) using the page
    // pixels, before reading order and framing. Re-check cancellation: the scan can run off-main.
    let filtered = await PanelContentFilter.filtered(detection, pageImage: image)
    guard !Task.isCancelled else { return .empty }

    // Readability paths need OCR lines: a wide panel (sub-views) or a panel-less page that still has
    // dialogue (the borderless-scene paths). Pay for the OCR pass only in those cases (most pages have neither),
    // and only when a Vision provider is wired. The wide-panel sub-walk applies only to two-page
    // spreads, so single pages never need OCR for it; a spread's panel geometry is measured in
    // single-page units (×2), and the legibility step still decides later.
    let pageIsSpread = image.width > image.height
    let hasWidePanel =
      pageIsSpread
      && filtered.panels.contains {
        $0.height > 0
          && $0.width * 2 >= PanelComposition.wideMinPageWidthFraction
          && ($0.width / $0.height) * 2 >= PanelComposition.wideAspectMin
      }
    let panelLessWithText = filtered.panels.isEmpty && !filtered.texts.isEmpty
    var ocrLines: [PanelRect] = []
    if let visionText, hasWidePanel || panelLessWithText, scriptCache.shouldRunOCR(bookId: bookId) {
      ocrLines = await visionText.detectText(image: image)
      guard !Task.isCancelled else { return .empty }
      // Learn the book's orientation: OCR text => horizontal (Latin); OCR empty on a text-bearing
      // page => evidence of vertical CJK. Once locked vertical, later pages skip OCR above.
      scriptCache.record(
        bookId: bookId, ocrFoundLines: !ocrLines.isEmpty, detectorHasText: !filtered.texts.isEmpty)
    }

    // Full-bleed art reads better whole than closed-in. Only a splash-eligible page can take
    // a splash beat — a single panel, or a borderless page with a figure — so only those pay for the
    // ring-density pixel scan.
    let splashEligible =
      filtered.panels.count == 1
      || (filtered.panels.isEmpty && !filtered.bodies.isEmpty)
    let pageIsFullBleed = splashEligible ? await PanelContentFilter.isFullBleed(image) : false
    guard !Task.isCancelled else { return .empty }

    // The reading-order gutter probe verifies cut candidates against the page pixels;
    // only multi-panel pages order through cuts, so only they pay for the mask.
    let raster = filtered.panels.count >= 2 ? await PanelPageRaster.make(from: image) : nil
    guard !Task.isCancelled else { return .empty }

    let composed = PanelComposition.compose(
      filtered, direction: presentation.direction, ocrLines: ocrLines,
      pageIsSpread: pageIsSpread, pageIsFullBleed: pageIsFullBleed, raster: raster)
    // Reading order is decided on the original page; only the rects move into the displayed page
    // (rotation, border crop). The crop measurement scans pixels, so it runs off the main actor.
    let sequence =
      presentation.transformsPage
      ? await Task.detached(priority: .utility) { presentation.displayed(composed, in: image) }.value
      : composed
    guard !Task.isCancelled else { return .empty }
    // DEBUG: ordering diagnostics — direction + each beat's x-center, so the device walk order is
    // visible (RTL → first beat on the right). Strip before fold.
    if case .panels(let beats) = sequence {
      let xs = beats.map { String(format: "%.2f", $0.x + $0.width / 2) }.joined(separator: " ")
      #if DEBUG
        // DEBUG: append the body-class-combine breakdown (orphan vs spanning figures + overlaps) to the
        // same line, so one `PanelOrder` filter shows the walk AND why a contact pair did/didn't merge.
        // Strip before fold.
        let bc = " :: " + PanelComposition.debugFigureBeats(filtered, direction: presentation.direction)
      #else
        let bc = ""
      #endif
      logger.debug(
        "[PanelOrder] dir=\(presentation.direction.rawValue) page=\(page.number) beats=\(beats.count) cx=[\(xs)]\(bc)")
    } else {
      logger.debug("[PanelOrder] dir=\(presentation.direction.rawValue) page=\(page.number) seq=non-panels")
    }
    await cache.store(sequence, for: key.fingerprint)
    return sequence
  }

  private func makeKey(bookId: String, page: BookPage, presentation: PanelPagePresentation) -> PanelCacheKey {
    PanelCacheKey(
      instanceId: CacheNamespace.identifier(),
      bookId: bookId,
      page: page,
      // Fold the Vision version into the detector version so toggling or changing the Vision
      // pass invalidates cached sequences that depended on it.
      detectorVersion: provider.version + (visionText.map { "+" + $0.version } ?? ""),
      presentation: presentation
    )
  }
}
