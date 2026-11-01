//
// PanelTextScriptCache.swift
//
// Per-book text-orientation memory that gates the OCR pass. OCR (`VisionTextProvider`) reads
// horizontal/Latin text but is blind to vertical CJK, so on a CJK book every qualifying page would
// otherwise pay an OCR pass that returns nothing. This store learns a book's orientation from the
// OCR-empty signal (Komga language metadata is unreliable, so it is never used) and, once a book is
// known vertical/CJK, tells the orchestrator to skip OCR entirely — the panel-less bubble-walk then
// uses the detector text size (min side) instead, which is the same result OCR-empty would yield.
//
// This is deliberately SEPARATE from `PanelSequenceCache`: that cache is per-PAGE and bounded by a
// TTL + entry budget that churns as you page through a book, whereas this is a per-BOOK hint that must
// outlive that churn. It is also output-invariant (skipping OCR == running it and getting empty), so it
// must not enter the sequence-cache key. In-memory only (derived, cheap to relearn); not persisted.
//

import Foundation

@MainActor
final class PanelTextScriptCache {
  /// A book's learned text orientation. `unknown`/`horizontal` run OCR; `vertical` skips it.
  enum Script: Equatable {
    /// Not yet determined — run OCR and learn from the result.
    case unknown
    /// Latin/horizontal: OCR reads it, and the readability gate needs its per-line counts, so OCR
    /// keeps running. Sticky — a book that ever yields real OCR text stays horizontal.
    case horizontal
    /// CJK/vertical: OCR is blind here, so skip it and let the bubble-walk use the detector text size.
    case vertical
  }

  /// Vertical is locked only after this many text-bearing pages where OCR found nothing, so a single
  /// OCR miss on a Latin page (low contrast, stylized) cannot mislock a book into skipping OCR.
  private let verticalEvidenceThreshold: Int

  private var scripts: [String: Script] = [:]
  private var verticalEvidence: [String: Int] = [:]

  init(verticalEvidenceThreshold: Int = 2) {
    self.verticalEvidenceThreshold = verticalEvidenceThreshold
  }

  /// Whether to run the OCR pass for this book. False only once the book is known vertical/CJK.
  func shouldRunOCR(bookId: String) -> Bool {
    scripts[bookId, default: .unknown] != .vertical
  }

  /// The learned script for a book (diagnostics / tests).
  func script(bookId: String) -> Script {
    scripts[bookId, default: .unknown]
  }

  /// Fold one OCR outcome into the book's learned script. `ocrFoundLines` = OCR returned at least one
  /// line; `detectorHasText` = the detector found text bubbles on the page (so an empty OCR result is
  /// meaningful evidence of vertical text rather than just a textless page).
  func record(bookId: String, ocrFoundLines: Bool, detectorHasText: Bool) {
    if scripts[bookId] == .horizontal { return }
    if ocrFoundLines {
      scripts[bookId] = .horizontal
      verticalEvidence[bookId] = 0
      return
    }
    guard detectorHasText else { return }
    let evidence = (verticalEvidence[bookId] ?? 0) + 1
    verticalEvidence[bookId] = evidence
    if evidence >= verticalEvidenceThreshold {
      scripts[bookId] = .vertical
    }
  }

  func removeAll() {
    scripts.removeAll()
    verticalEvidence.removeAll()
  }
}
