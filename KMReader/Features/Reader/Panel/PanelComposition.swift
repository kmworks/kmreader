//
// PanelComposition.swift
//
// Detector-agnostic step that turns a PageDetection into the reader's PanelSequence. It orders the
// strict panels into reading order, then composes the content-aware walk:
//   - dialogue framing: each panel's zoom rect grows to include the text bubble that belongs to it
//     (the panel holding the largest fraction of the text box), so a bubble spilling over a
//     neighbor's border is still shown with its own panel.
//   - figure-spanning body beats: a character drawn across 2+ genuinely-distinct panels gets its own
//     zoom beat (the full body box), placed next to the panel it is the subject of, e.g. the walk
//     `0 1 2 3` becomes `0 1 2-body 2 3` (or `0 1 2 2-body 3` when the figure reads after its panel).
//   - orphan figures: on a multi-panel page, a body drawn outside every panel (a panel the detector
//     missed) becomes its own beat, ordered among the panels through the same reading-order cut.
//   - borderless pages: a page with a dialogue exchange is a scene with a reading sequence, so it
//     walks like a regular page (speech clusters + figures as beats); without one it is a single
//     viewing event — full-bleed art shows whole, a croppable subject gets one splash zoom then a
//     page turn (no trailing whole-page) — see `compose`.
// This is the one place these features live, so every provider shares the same pipeline. The fractions
// are scale-invariant, so they apply directly to normalized [0,1] boxes.
//

import Foundation

nonisolated enum PanelComposition {
  /// A text bubble is framed into the panel holding at least this fraction of the text box; below
  /// it the text is a free-floating orphan with no owner (orphan handling is a later rule).
  static let textAssignMinFraction = 0.10
  /// A body must cover at least this fraction of ITSELF inside a panel to count as touching it.
  static let bodyTouchFraction = 0.15
  /// Two touched panels overlapping each other by less than this (fraction of the smaller) are
  /// genuinely distinct, so a body across them is figure-spanning rather than a nested annotation
  /// inside overlapping frames.
  static let spanningPanelMaxOverlap = 0.10
  /// A figure earns a body beat if it fills at least this fraction of its OWNER PANEL's area (it
  /// dominates that panel). Set so a figure must clearly own its panel, not merely half-fill it: a
  /// mid-ground figure that only clips a neighbouring panel (around half its owner's area, and not
  /// tall) is already legible in the normal walk and does not warrant its own zoom.
  static let bodyMinPanelFraction = 0.55
  /// ... OR its height reaches at least this fraction of the panel CONTENT height (the panels'
  /// vertical extent, which is padding-invariant unlike raw page height). The relative test catches
  /// figures that dominate their panel; this absolute test rescues a tall major figure sitting in a
  /// big panel (low area fraction but clearly prominent). A figure failing both — a tiny head, or a
  /// minor figure small in a big panel — gets no beat (already legible in the normal walk).
  static let bodyMinContentHeight = 0.50
  /// Near-splash for a panel-less page that still has a figure (`body`). When the figures are
  /// LOCALIZED — their union covers less than `nearSplashZoomMaxCoverage` of the page (small figures
  /// in a sea of whitespace, e.g. a corner group) — the beat zooms to the padded content box (bodies
  /// + texts; unioning the texts keeps speech in frame). When the figures FILL the page (a borderless
  /// scene, chapter-splash art, or a cover) zooming to them "closes in" and loses the composition, so
  /// the beat is a gentle uniform crop inset by `nearSplashInset` instead. A text-only / blank page
  /// has no figure to anchor it, so it stays whole-page (no extra tap).
  static let nearSplashZoomMaxCoverage = 0.30
  static let nearSplashPadding = 0.04
  static let nearSplashInset = 0.10
  /// An orphan figure (a body inside no panel) earns its own beat only when it reaches at least this
  /// fraction of the page height ...
  static let orphanMinHeight = 0.08
  /// ... AND this fraction of the page area — below both it is a speck, not a figure worth a beat.
  static let orphanMinArea = 0.006
  /// A body covered by some panel by at least this fraction of itself belongs to that panel (it is
  /// part of a panel's scene), so it is not an orphan.
  static let orphanContainment = 0.5

  // MARK: Borderless-scene walk (the dialogue-sequence rule)
  // A borderless page with a dialogue EXCHANGE is a scene with a reading sequence — dialogue is
  // what sequences a reader's attention — so it walks like a regular page (trailing whole-page
  // bookend and back-navigation included). Without an exchange the page is a single viewing
  // event: full-bleed art shows whole, a croppable subject gets one splash zoom.
  /// An exchange needs interlocutors: at least this many figures alongside `sceneMinSpeech`
  /// speech bubbles...
  static let sceneMinFigures = 2
  static let sceneMinSpeech = 2
  /// ...or a sustained monologue: at least this many bubbles regardless of figure count. A single
  /// figure with fewer texts is a declaration or a title pin-up — one impression, so it stays a
  /// splash rather than fragmenting into taps.
  static let sceneMonologueSpeech = 3
  /// More merged figures than this is a crowd: the ensemble is the subject and is already visible
  /// in the whole-page bookends, so only the dialogue is walked.
  static let sceneMaxFigureBeats = 3
  /// A figure covering more than this fraction of the page IS the scene — the whole-page bookends
  /// already show it, so a beat would only re-show the page at a slight zoom.
  static let sceneMaxFigureArea = 0.5
  /// Two orphan figures that overlap by at least this fraction of the smaller one's area belong to one
  /// borderless scene the detector split into separate boxes (a grab, a facing greeting), so they merge
  /// into one beat (see `mergeContactingBodies`) instead of zooming to each in turn. Tuned to the
  /// on-device contact overlaps — a wrist-grab reads ~0.18, a bowing greeting ~0.05 — and set just below
  /// 0.05 so the greeting case clears it reliably (the log rounds to two places).
  static let bodyCombineOverlap = 0.04
  /// ... but a cluster whose merged box would exceed this fraction of the page is more likely unrelated
  /// figures chained together than one scene, so it stays as separate beats (the anti-chaining guard).
  static let bodyCombineMaxUnionArea = 0.40

  // MARK: Side-column reading order
  /// When the panels are confined to one side of the page, leaving at least this fraction of page
  /// width free on the other side, and the orphan bodies all sit in that free margin, the orphans form
  /// a borderless column read as a unit (on the reading-leading side first) rather than being row-major
  /// interleaved with the panels by the page-wide X-Y cut.
  static let sideColumnMinFree = 0.25

  // MARK: Wide-panel readability (overview + readable sub-views)
  // A panel sub-walks only when it is a genuine wide band whose text is too small to read at
  // fit-to-viewport-width zoom. Three conditions gate it, the first two measured in SINGLE-PAGE units
  // (a landscape spread holds two pages, so width and aspect are doubled — see `wideSubviews`): the
  // panel spans most of a page width, it is a wide band, and its median text line falls below the
  // legibility floor. Each rules out a way the text stays readable on its own: a narrower panel
  // enlarges its text when fit to the viewport width (a half-width panel doubles it), a squarer panel
  // is not a thin band, and larger text needs no panning.
  /// A panel must span at least this fraction of a single page's width to sub-walk: below it, fit-width
  /// zoom already enlarges the text enough that horizontal panning would only add taps for no gain.
  static let wideMinPageWidthFraction = 0.85
  /// ... and be at least this wide (width / height) — a genuine thin band. Square and tall panels read
  /// comfortably at fit-width, so they never sub-walk.
  static let wideAspectMin = 2.6
  /// Reference portrait viewport aspect (width / height) used to estimate rendered text size at
  /// fit-width zoom. A fixed value keeps composition UI-free and the sequence cache rotation-stable;
  /// dynamic per-device aspect is a possible refinement.
  static let wideReferenceViewportAspect = 0.46
  /// Gate: a wide panel sub-walks when its median in-panel text line, rendered at fit-width zoom, would
  /// be below this fraction of screen height (too small to read comfortably). Calibrated for OCR line
  /// boxes (single lines); a coarser multi-line text source would want a higher floor.
  static let wideLegibilityFloor = 0.013
  /// Split target: size each sub-view so its text renders at about this fraction of screen height.
  static let wideTargetTextFraction = 0.050
  /// Sub-view padding as a fraction of the panel width.
  static let widePadFraction = 0.02
  /// Cap on sub-views per wide panel; clusters beyond this merge (cheapest adjacent pair first) so a
  /// panel never costs too many taps.
  static let wideMaxSubviews = 3
  /// In-panel text taller than this multiple of the panel median is SFX / a title / a logo, so it is
  /// discounted from the gate and the split (it does not seed a sub-view).
  static let wideLargeTextMultiple = 2.2

  // MARK: Borderless-scene columns (speech-cluster beats for the scene walk)
  /// A detector text bubble taller than this multiple of the page-median is a title / banner and is
  /// discounted so it neither skews the walk gate nor seeds a stray column.
  static let bubbleLargeTextMultiple = 2.2
  /// A vertical gap (no bubble) wider than this fraction of page width splits one column from the next.
  static let columnGutterFraction = 0.035
  /// A column wider than this fraction of page width sub-splits at its widest internal gap (RTL pieces).
  static let columnComfortWidthFraction = 0.46
  /// A column taller than this fraction of page height sub-splits at its widest internal gap (top/bottom).
  static let columnComfortHeightFraction = 0.55
  /// Padding around each column beat, as a fraction of page width.
  static let columnPadFraction = 0.01

  /// Build the reader walk from a page's detection. Panels and orphan figures (bodies drawn outside
  /// every panel, e.g. on a borderless page or where the detector missed a panel) are ordered
  /// together so each lands in its geometric reading slot. A page with neither yields `.empty` so
  /// the reader shows the whole page.
  /// `ocrLines` are Apple Vision OCR line boxes feeding the readability paths (wide-panel sub-views and
  /// the full-bleed legibility override on the borderless-scene walk); empty signals vertical CJK,
  /// where legibility falls back to the detector text size. The detector's own `texts` drive
  /// dialogue framing and the scene walk itself, which needs no OCR.
  /// `pageIsSpread` is true when the page image is a landscape two-page spread, so the wide-panel gate
  /// measures panel width and aspect in single-page units.
  /// `pageIsFullBleed` is true when the art runs to the page edges, so a splash beat would "close in"
  /// and lose the composition — such a page stays whole-page instead (full-page or full-height art).
  static func compose(
    _ detection: PageDetection, direction: ReadingDirection,
    ocrLines: [PanelRect] = [], pageIsSpread: Bool = false, pageIsFullBleed: Bool = false,
    raster: PanelPageRaster? = nil
  ) -> PanelSequence {
    let strict = PanelReadingOrder.ordered(detection.panels, direction: direction, raster: raster)
    let extended = framed(strict, with: detection.texts)

    // Single-beat-then-turn pages (no trailing whole-page bookend):
    //  - one panel of any size is a splash: show the page, zoom the (framed) art, turn.
    //  - no panels but a figure present is a near-splash: LOCALIZED figures (small in a sea of
    //    whitespace) zoom to the padded content box; page-filling figures (a borderless scene,
    //    chapter-splash art, or a cover) get only a gentle uniform crop so the composition is not
    //    closed in on. Gating on a `body` keeps text-only pages (chapter lists, afterwords) and
    //    blank pages on whole-page, no extra tap.
    if strict.count == 1 {
      // Full-bleed single-panel art (the panel runs to the page edges) reads better whole than
      // closed-in; otherwise zoom the framed panel.
      return pageIsFullBleed ? .empty : .splash(extended[0])
    }
    if strict.isEmpty {
      // Borderless pages classify by the dialogue-sequence rule (see the scene-walk constants):
      // an EXCHANGE means the page has a reading sequence, so it walks like a regular page;
      // otherwise it is a single viewing event (whole page, or one splash zoom to the subject).
      let bubbles = discountTallText(PanelTextReadability.bubbles(detection.texts))
      let exchange =
        !detection.bodies.isEmpty
        && (bubbles.count >= sceneMonologueSpeech
          || (detection.bodies.count >= sceneMinFigures && bubbles.count >= sceneMinSpeech))
      // Full-bleed art (figures + scenery running to the page edges) loses its composition when
      // closed-in, so it shows whole — unless it carries an exchange the reader cannot read at
      // whole-page zoom, where legibility overrides composition and the scene still walks.
      if pageIsFullBleed {
        if exchange, !PanelTextReadability.isReadable(bubbles: bubbles, ocrLines: ocrLines),
          let walk = sceneWalk(bubbles: bubbles, bodies: detection.bodies, direction: direction)
        {
          return walk
        }
        return .empty
      }
      if exchange, let walk = sceneWalk(bubbles: bubbles, bodies: detection.bodies, direction: direction) {
        return walk
      }
      // No exchange: a text-only page with no figure is prose / a chapter index / credits / an
      // afterword, read normally, so it stays whole-page. A page with figures gets one splash
      // zoom: to the padded content box when the figures are localized, else a gentle uniform
      // crop so a page-filling composition is not closed in on.
      guard !detection.bodies.isEmpty else { return .empty }
      if area(boundingBox(detection.bodies, padding: 0)) < nearSplashZoomMaxCoverage {
        return .splash(boundingBox(detection.bodies + detection.texts, padding: nearSplashPadding))
      }
      return .splash(
        PanelRect(
          x: nearSplashInset, y: nearSplashInset,
          width: 1 - 2 * nearSplashInset, height: 1 - 2 * nearSplashInset))
    }

    // Multi-panel walk. An orphan figure (a body in an undetected/borderless region) still earns a
    // beat, ordered among the panels through one X-Y cut, so a panel the detector missed is
    // recovered. `combined` holds the strict panels first (index < panel count = that panel's
    // rank), then the orphans.
    let spans = spanningBodies(strict: strict, bodies: detection.bodies)
    let spanningRects = spans.values.flatMap { $0.map { $0.body } }
    let orphans = mergeContactingBodies(orphanBodies(detection.bodies, panels: strict, spanning: spanningRects))
    let ocrByPanel = assignOCRLines(ocrLines, to: strict)
    let perPanel = panelBeats(
      strict: strict, extended: extended, spans: spans,
      ocrByPanel: ocrByPanel, direction: direction, pageIsSpread: pageIsSpread)
    let combined = strict + orphans
    // A side-confined panel column beside a borderless orphan column reads as two columns (the
    // borderless side first in RTL), not row-major; fall back to the page-wide X-Y cut otherwise.
    let order =
      sideColumnOrder(strict: strict, orphans: orphans, direction: direction)
      ?? PanelReadingOrder.ordered(
        Array(combined.indices), rect: { combined[$0] }, direction: direction, raster: raster)

    var beats: [PanelRect] = []
    for index in order {
      if index < strict.count {
        beats.append(contentsOf: perPanel[index])
      } else {
        beats.append(combined[index])  // orphan figure: its own beat
      }
    }
    guard !beats.isEmpty else { return .empty }
    return .panels(beats)
  }

  #if DEBUG
    /// DEBUG (body-class combine): the figure-beat breakdown for a multi-panel page — are the stray
    /// figures ORPHAN (out-of-panel) or SPANNING (drawn across panels), and what is each figure pair's
    /// overlap-of-smaller? Reveals why a grapple/contact pair did or did not merge. Strip before fold.
    static func debugFigureBeats(_ detection: PageDetection, direction: ReadingDirection) -> String {
      let strict = PanelReadingOrder.ordered(detection.panels, direction: direction)
      guard strict.count >= 2 else { return "n/a (panels=\(strict.count))" }
      let spans = spanningBodies(strict: strict, bodies: detection.bodies)
      let spanningRects = spans.values.flatMap { $0.map { $0.body } }
      let orphans = orphanBodies(detection.bodies, panels: strict, spanning: spanningRects)
      let merged = mergeContactingBodies(orphans)
      func cx(_ r: PanelRect) -> String { String(format: "%.2f", r.x + r.width / 2) }
      func list(_ rs: [PanelRect]) -> String { rs.map(cx).joined(separator: ",") }
      let figures = orphans + spanningRects
      var pairs: [String] = []
      for a in figures.indices {
        for b in (a + 1)..<figures.count {
          let ov = panelOverlapFraction(figures[a], figures[b])
          if ov > 0.001 { pairs.append("\(cx(figures[a]))~\(cx(figures[b]))=\(String(format: "%.2f", ov))") }
        }
      }
      return
        "panels=\(strict.count) orphans=[\(list(orphans))]->merged=[\(list(merged))] spanning=[\(list(spanningRects))] overlaps=[\(pairs.joined(separator: " "))]"
    }
  #endif

  // MARK: - Dialogue framing

  /// Each panel's zoom rect grown to include the text boxes assigned to it. Panels keep their input
  /// (reading) order; only the rects grow.
  private static func framed(_ panels: [PanelRect], with texts: [PanelRect]) -> [PanelRect] {
    var ext = panels
    for text in texts {
      guard let owner = assignedPanel(for: text, in: panels) else { continue }
      ext[owner] = union(ext[owner], text)
    }
    return ext
  }

  /// Index of the panel holding the largest fraction of the text box, or nil if even the best is
  /// below the assignment floor (free-floating text → orphan, handled by a later rule).
  private static func assignedPanel(for text: PanelRect, in panels: [PanelRect]) -> Int? {
    let textArea = area(text)
    guard textArea > 0 else { return nil }
    var best: Int?
    var bestFraction = 0.0
    for (i, panel) in panels.enumerated() {
      let fraction = interArea(text, panel) / textArea
      if fraction > bestFraction {
        bestFraction = fraction
        best = i
      }
    }
    return bestFraction >= textAssignMinFraction ? best : nil
  }

  // MARK: - Walk + figure-spanning body beats

  /// Per-panel beats keyed by reading-order index: each panel's extended rect with its figure-
  /// spanning body beats placed relative to it. ONE figure in a panel is placed by the panel it
  /// bridges — before the panel if it also reaches an earlier-read panel (it leads in from where
  /// you've been), after if it reaches only a later-read panel (it leads out to what's next).
  /// MULTIPLE figures in one panel bridge the same neighbors, so they split by position instead:
  /// right-of-center reads before the panel, left-of-center after (rightmost-first within a side,
  /// for RTL). Mirrored for LTR. Returned grouped (not flattened) so the caller can interleave
  /// orphan-figure beats between panels by the combined reading order.
  private static func panelBeats(
    strict: [PanelRect], extended: [PanelRect],
    spans: [Int: [(body: PanelRect, touched: [Int])]],
    ocrByPanel: [[PanelRect]], direction: ReadingDirection, pageIsSpread: Bool
  ) -> [[PanelRect]] {
    let rtl = direction == .rtl
    let readingFirst: (PanelRect, PanelRect) -> Bool = { a, b in
      let ca = a.x + a.width / 2
      let cb = b.x + b.width / 2
      return rtl ? ca > cb : ca < cb
    }

    var result = [[PanelRect]](repeating: [], count: strict.count)
    for i in strict.indices {
      let group = spans[i, default: []]
      var before: [PanelRect] = []
      var after: [PanelRect] = []
      if group.count == 1 {
        let (body, touched) = group[0]
        let others = touched.filter { $0 != i }
        if !others.isEmpty, others.allSatisfy({ $0 > i }) { after.append(body) } else { before.append(body) }
      } else {
        let center = strict[i].x + strict[i].width / 2
        for (body, _) in group {
          let isBefore = rtl ? (body.x + body.width / 2 > center) : (body.x + body.width / 2 < center)
          if isBefore { before.append(body) } else { after.append(body) }
        }
      }
      // The panel's own beat: a wide panel with small text becomes overview + readable sub-views,
      // otherwise the single framed rect.
      let main = wideMainBeats(
        panel: extended[i], ocrLines: ocrByPanel[i],
        direction: direction, pageIsSpread: pageIsSpread)
      result[i] = before.sorted(by: readingFirst) + main + after.sorted(by: readingFirst)
    }
    return result
  }

  // MARK: - Wide-panel readability

  /// Vision text boxes bucketed by the strict panel that owns the largest fraction of each (below the
  /// assignment floor a box belongs to no panel). Empty input yields empty buckets (feature off).
  private static func assignOCRLines(_ texts: [PanelRect], to panels: [PanelRect]) -> [[PanelRect]] {
    var byPanel = [[PanelRect]](repeating: [], count: panels.count)
    for text in texts {
      if let owner = assignedPanel(for: text, in: panels) { byPanel[owner].append(text) }
    }
    return byPanel
  }

  /// A panel's beat list: `[overview, sub[0], sub[1], …]` when the panel is too wide to read its text
  /// at fit-width zoom, else just `[panel]`. The overview is the panel rect itself; it is a normal
  /// beat, so it is symmetric (shown stepping back too) — only page-boundary bookends are forward-only.
  private static func wideMainBeats(
    panel: PanelRect, ocrLines: [PanelRect], direction: ReadingDirection, pageIsSpread: Bool
  ) -> [PanelRect] {
    guard
      let subs = wideSubviews(
        panel: panel, ocrLines: ocrLines,
        direction: direction, pageIsSpread: pageIsSpread)
    else {
      return [panel]
    }
    return [panel] + subs
  }

  /// Sub-view rects panning across a wide panel in reading order, or nil if the panel does not qualify.
  /// The text-size sub-walk applies ONLY to two-page spreads — a panel spanning a spread is
  /// unambiguously too small to read at fit-width on any device. On a single page the same decision
  /// depends on physical screen size (which the fixed reference viewport cannot capture) and the must-
  /// walk and reads-fine cases are not separable from the boxes, so single pages keep the whole framed
  /// panel as one beat. Gate (spread, in single-page units): width ≥
  /// `wideMinPageWidthFraction` AND aspect ≥ `wideAspectMin` AND median in-panel (non-oversized) text,
  /// rendered at fit-width zoom, below `wideLegibilityFloor`. Split: cluster the text in reading order
  /// into views each about `wideTargetTextFraction` tall, capped at `wideMaxSubviews`.
  private static func wideSubviews(
    panel: PanelRect, ocrLines: [PanelRect], direction: ReadingDirection, pageIsSpread: Bool
  ) -> [PanelRect]? {
    guard pageIsSpread else { return nil }
    // A landscape spread holds two pages, so the panel's width and aspect are doubled to single-page
    // units; legibility stays measured against the actual image (the rendered text size is the same).
    let pageUnits = 2.0
    guard panel.height > 0,
      panel.width * pageUnits >= wideMinPageWidthFraction,
      (panel.width / panel.height) * pageUnits >= wideAspectMin
    else { return nil }
    let inside = ocrLines.filter { contained($0, in: panel) >= 0.5 }
    let body = discountLargeText(inside)
    guard body.count >= 2 else { return nil }

    let medianHeight = median(body.map(\.height))
    let legibility = (medianHeight / panel.width) * wideReferenceViewportAspect
    guard legibility < wideLegibilityFloor else { return nil }

    let subs = splitWide(panel: panel, body: body, medianHeight: medianHeight, direction: direction)
    return subs.count >= 2 ? subs : nil
  }

  /// Drop in-panel text much taller than the median (SFX / titles / logos) so it neither skews the
  /// gate nor seeds a sub-view.
  private static func discountLargeText(_ texts: [PanelRect]) -> [PanelRect] {
    guard !texts.isEmpty else { return [] }
    let cutoff = wideLargeTextMultiple * median(texts.map(\.height))
    return texts.filter { $0.height <= cutoff }
  }

  /// Greedily cluster the panel's text in reading order into sub-views each at most `widthTarget` wide, then
  /// merge the cheapest adjacent pair until within the cap. Each view is full panel height (pan
  /// horizontally), padded and clamped to the panel.
  private static func splitWide(
    panel: PanelRect, body: [PanelRect], medianHeight: Double, direction: ReadingDirection
  ) -> [PanelRect] {
    let rtl = direction == .rtl
    let widthTarget = medianHeight * wideReferenceViewportAspect / wideTargetTextFraction
    let ordered = body.sorted { a, b in
      let ca = a.x + a.width / 2
      let cb = b.x + b.width / 2
      return rtl ? ca > cb : ca < cb
    }

    var clusters: [[PanelRect]] = []
    var current: [PanelRect] = []
    for text in ordered {
      if !current.isEmpty {
        let x0 = min(current.map(\.x).min()!, text.x)
        let x1 = max(current.map { $0.x + $0.width }.max()!, text.x + text.width)
        if x1 - x0 > widthTarget {
          clusters.append(current)
          current = []
        }
      }
      current.append(text)
    }
    if !current.isEmpty { clusters.append(current) }

    func extent(_ cluster: [PanelRect]) -> Double {
      cluster.map { $0.x + $0.width }.max()! - cluster.map(\.x).min()!
    }
    while clusters.count > wideMaxSubviews {
      var bestIndex = 0
      var bestWidth = Double.greatestFiniteMagnitude
      for i in 0..<(clusters.count - 1) {
        let merged = extent(clusters[i] + clusters[i + 1])
        if merged < bestWidth {
          bestWidth = merged
          bestIndex = i
        }
      }
      clusters[bestIndex] += clusters[bestIndex + 1]
      clusters.remove(at: bestIndex + 1)
    }

    let pad = widePadFraction * panel.width
    return clusters.map { cluster in
      let x0 = max(panel.x, cluster.map(\.x).min()! - pad)
      let x1 = min(panel.x + panel.width, cluster.map { $0.x + $0.width }.max()! + pad)
      return PanelRect(x: x0, y: panel.y, width: max(0, x1 - x0), height: panel.height)
    }
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
  }

  // MARK: - Borderless-scene walk (content-aware columns + figures)

  /// A borderless dialogue scene walked like a regular page. The speech clusters (bubble columns at
  /// natural gutters, comfort-split so no beat is too wide or tall) are the text beats; a figure
  /// overlapping a cluster unions into that beat — an overlapping figure is unambiguously part of
  /// the unit, while attaching by mere proximity risks pairing text with the wrong figure, so
  /// separated figures stay separate beats. Size-gated, contact-merged figures add their own beats
  /// unless they outnumber the crowd cap. Beats walk in reading order through the shared X-Y cut;
  /// the leading/trailing whole-page bookends give the overview. Returns nil when everything
  /// collapses into a single beat (one unit reads as a splash, not a walk).
  private static func sceneWalk(
    bubbles: [PanelRect], bodies: [PanelRect], direction: ReadingDirection
  ) -> PanelSequence? {
    guard bubbles.count >= sceneMinSpeech else { return nil }
    var cells = contentColumns(bubbles, direction: direction)
      .map { boundingBox($0, padding: columnPadFraction) }
    var figures = mergeContactingBodies(
      bodies.filter {
        $0.height >= orphanMinHeight && area($0) >= orphanMinArea
      }
    ).filter { area($0) <= sceneMaxFigureArea }
    if figures.count > sceneMaxFigureBeats { figures = [] }

    var standalone: [PanelRect] = []
    for figure in figures {
      var bestIndex: Int?
      var bestOverlap = 0.0
      for (i, cell) in cells.enumerated() {
        let overlap = interArea(figure, cell)
        if overlap > bestOverlap {
          bestOverlap = overlap
          bestIndex = i
        }
      }
      if let i = bestIndex {
        cells[i] = union(cells[i], figure)
      } else {
        standalone.append(figure)
      }
    }
    let beats = cells + standalone
    guard beats.count >= 2 else { return nil }
    return .panels(PanelReadingOrder.ordered(beats, direction: direction))
  }

  /// Drop detector text boxes much taller than the page median (a chapter title / banner) so they do
  /// not skew the readability gate or seed a stray column.
  private static func discountTallText(_ bubbles: [PanelRect]) -> [PanelRect] {
    guard !bubbles.isEmpty else { return [] }
    let cutoff = bubbleLargeTextMultiple * median(bubbles.map(\.height))
    return bubbles.filter { $0.height <= cutoff }
  }

  /// Vertical columns by natural gutters (RTL), each comfort-split by width then height. Returns the
  /// final cells (bubble groups) in reading order, each ordered top-to-bottom.
  private static func contentColumns(_ bubbles: [PanelRect], direction: ReadingDirection) -> [[PanelRect]] {
    let rtl = direction == .rtl
    var columns: [[PanelRect]] = []
    var current: [PanelRect] = []
    var rightEdge: Double?
    for bubble in bubbles.sorted(by: { $0.x < $1.x }) {
      if let edge = rightEdge, bubble.x - edge > columnGutterFraction {
        columns.append(current)
        current = []
        rightEdge = nil
      }
      current.append(bubble)
      rightEdge = max(rightEdge ?? -.greatestFiniteMagnitude, bubble.x + bubble.width)
    }
    if !current.isEmpty { columns.append(current) }
    if rtl { columns.reverse() }

    return columns.flatMap { comfortSplit($0, rtl: rtl) }
  }

  /// Recursively split a bubble group into comfort cells: too wide → vertical cut at the widest
  /// internal gap (RTL pieces); else too tall → horizontal cut at the widest internal gap (top/bottom);
  /// else the group as one cell, ordered top-to-bottom.
  private static func comfortSplit(_ group: [PanelRect], rtl: Bool) -> [[PanelRect]] {
    let box = boundingBox(group, padding: 0)
    if group.count > 1, box.width > columnComfortWidthFraction {
      let xs = group.sorted { $0.x < $1.x }
      let k = widestGapIndex(xs.map { (lo: $0.x, hi: $0.x + $0.width) })
      let left = Array(xs[...k])
      let right = Array(xs[(k + 1)...])
      let (first, second) = rtl ? (right, left) : (left, right)
      return comfortSplit(first, rtl: rtl) + comfortSplit(second, rtl: rtl)
    }
    if group.count > 1, box.height > columnComfortHeightFraction {
      let ys = group.sorted { $0.y < $1.y }
      let k = widestGapIndex(ys.map { (lo: $0.y, hi: $0.y + $0.height) })
      let top = Array(ys[...k])
      let bottom = Array(ys[(k + 1)...])
      return comfortSplit(top, rtl: rtl) + comfortSplit(bottom, rtl: rtl)
    }
    return [group.sorted { $0.y < $1.y }]
  }

  /// Index after which the widest gap to the next interval falls (intervals already sorted by `lo`).
  private static func widestGapIndex(_ intervals: [(lo: Double, hi: Double)]) -> Int {
    var best = 0
    var bestGap = -Double.greatestFiniteMagnitude
    for j in 0..<(intervals.count - 1) {
      let gap = intervals[j + 1].lo - intervals[j].hi
      if gap > bestGap {
        bestGap = gap
        best = j
      }
    }
    return best
  }

  // MARK: - Orphan figures

  /// Bodies drawn outside every panel (and not already a figure-spanning beat): a character on a
  /// borderless page, or one whose panel the detector missed. Each becomes its own beat, ordered
  /// among the panels by the combined X-Y cut. A speck below the size floor is skipped (not a
  /// figure worth zooming to), and a body covered by a panel is part of that panel's scene.
  private static func orphanBodies(
    _ bodies: [PanelRect], panels: [PanelRect], spanning: [PanelRect]
  ) -> [PanelRect] {
    bodies.filter { body in
      guard !spanning.contains(body) else { return false }
      let maxContained = panels.map { contained(body, in: $0) }.max() ?? 0
      guard maxContained < orphanContainment else { return false }
      return body.height >= orphanMinHeight && area(body) >= orphanMinArea
    }
  }

  /// Stray figures that physically overlap usually belong to ONE borderless scene the detector split
  /// into separate `body` boxes (a grappling pair, two people facing in a greeting). Walking them as
  /// separate beats zooms the reader to fragments of one moment, so cluster the orphans whose mutual
  /// overlap reaches `bodyCombineOverlap` of the smaller box (connected components) and replace each
  /// cluster with its union — one beat per scene. A cluster whose union would sprawl past
  /// `bodyCombineMaxUnionArea` is left as separate beats: that is more likely unrelated figures chained
  /// across the page than one scene. A no-op when no orphans touch, so it cannot regress loose,
  /// separated figures (e.g. a side-column pair).
  private static func mergeContactingBodies(_ orphans: [PanelRect]) -> [PanelRect] {
    guard orphans.count >= 2 else { return orphans }
    var parent = Array(orphans.indices)
    func find(_ i: Int) -> Int {
      var i = i
      while parent[i] != i {
        parent[i] = parent[parent[i]]
        i = parent[i]
      }
      return i
    }
    for a in orphans.indices {
      for b in (a + 1)..<orphans.count where panelOverlapFraction(orphans[a], orphans[b]) >= bodyCombineOverlap {
        parent[find(a)] = find(b)
      }
    }
    // Group members by cluster root, preserving first-appearance order (the X-Y cut reorders downstream).
    var clusters: [[Int]] = []
    var slot: [Int: Int] = [:]
    for i in orphans.indices {
      let root = find(i)
      if let s = slot[root] {
        clusters[s].append(i)
      } else {
        slot[root] = clusters.count
        clusters.append([i])
      }
    }
    var result: [PanelRect] = []
    for members in clusters {
      let rects = members.map { orphans[$0] }
      let merged = rects.dropFirst().reduce(rects[0], union)
      if rects.count == 1 || area(merged) <= bodyCombineMaxUnionArea {
        result.append(merged)  // one compact scene-beat
      } else {
        result.append(contentsOf: rects)  // too sprawling to be one scene → keep separate
      }
    }
    return result
  }

  /// When the panels are confined to one side of the page and every orphan figure sits in the free margin
  /// on the other side, those figures form a borderless column: order them as one unit (their own X-Y cut)
  /// read on the reading-leading side first (right column first for RTL), then the panels — instead of
  /// letting the page-wide X-Y cut row-major-split a tall borderless side-column. A SINGLE figure counts
  /// too (e.g. a body-class-combined scene that was two figures before the merge): one figure in the free
  /// margin still reads first in RTL, and the free-margin gate below still excludes an in-grid recovered
  /// orphan. Returns the combined-index order (`0..<strict.count` = panels, then orphans), or nil when the
  /// page is not this shape.
  private static func sideColumnOrder(
    strict: [PanelRect], orphans: [PanelRect], direction: ReadingDirection
  ) -> [Int]? {
    guard strict.count >= 2, orphans.count >= 1 else { return nil }
    let panelX0 = strict.map(\.x).min()!
    let panelX1 = strict.map { $0.x + $0.width }.max()!
    let orphansRight = (1 - panelX1) >= sideColumnMinFree && orphans.allSatisfy { $0.x + $0.width > panelX1 }
    let orphansLeft = panelX0 >= sideColumnMinFree && orphans.allSatisfy { $0.x < panelX0 }
    guard orphansRight || orphansLeft else { return nil }

    // Orphan column ordered on its own; panels keep their reading order (`strict` is already ordered).
    let orphanColumn =
      PanelReadingOrder
      .ordered(Array(orphans.indices), rect: { orphans[$0] }, direction: direction)
      .map { strict.count + $0 }
    let panelIndices = Array(0..<strict.count)
    let rtl = direction == .rtl
    let orphanFirst = (orphansRight && rtl) || (orphansLeft && !rtl)
    return orphanFirst ? orphanColumn + panelIndices : panelIndices + orphanColumn
  }

  /// Fraction of `inner`'s area that lies inside `outer`.
  private static func contained(_ inner: PanelRect, in outer: PanelRect) -> Double {
    let a = area(inner)
    return a > 0 ? interArea(inner, outer) / a : 0
  }

  /// Bodies drawn across 2+ genuinely-distinct panels, grouped by owner = the panel the body most
  /// DOMINATES (largest fraction of the panel covered by the body), not the earliest one it grazes
  /// nor the one holding the most body-pixels. A figure that only clips a big top panel but is the
  /// SUBJECT of a smaller lower panel anchors to the lower one. Each kept body carries its touched
  /// panel ranks (`strict` is already ordered, so a hit index IS its reading-order rank) for the walk
  /// placement. A body whose touched panels all overlap each other is a nested annotation, not
  /// spanning. SIZE GATE: a body must fill ≥ `bodyMinPanelFraction` of its owner panel's area, OR be
  /// ≥ `bodyMinContentHeight` of the panel content height — else it is too minor for its own beat.
  private static func spanningBodies(strict: [PanelRect], bodies: [PanelRect]) -> [Int: [(
    body: PanelRect, touched: [Int]
  )]] {
    guard !strict.isEmpty else { return [:] }
    let contentHeight = strict.map { $0.y + $0.height }.max()! - strict.map(\.y).min()!

    var byOwner: [Int: [(body: PanelRect, touched: [Int])]] = [:]
    for body in bodies {
      let bodyArea = area(body)
      guard bodyArea > 0 else { continue }
      let hits = strict.indices.filter { interArea(body, strict[$0]) / bodyArea >= bodyTouchFraction }
      guard hits.count >= 2, hasDistinctPair(hits, in: strict) else { continue }
      let owner = hits.max(by: { coverage(body, of: strict[$0]) < coverage(body, of: strict[$1]) })!
      let relOK = area(strict[owner]) > 0 && bodyArea / area(strict[owner]) >= bodyMinPanelFraction
      let absOK = contentHeight > 0 && body.height / contentHeight >= bodyMinContentHeight
      guard relOK || absOK else { continue }
      byOwner[owner, default: []].append((body, hits))
    }
    return byOwner
  }

  /// True if at least one pair of the touched panels is genuinely distinct (mutual overlap below
  /// the spanning threshold) — the figure bridges real panel borders, not overlapping frames.
  private static func hasDistinctPair(_ hits: [Int], in panels: [PanelRect]) -> Bool {
    for a in 0..<hits.count {
      for b in (a + 1)..<hits.count
      where panelOverlapFraction(panels[hits[a]], panels[hits[b]]) < spanningPanelMaxOverlap {
        return true
      }
    }
    return false
  }

  // MARK: - Geometry (normalized boxes)

  private static func area(_ r: PanelRect) -> Double { max(0, r.width) * max(0, r.height) }

  private static func interArea(_ a: PanelRect, _ b: PanelRect) -> Double {
    let iw = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
    let ih = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    return iw * ih
  }

  /// Intersection as a fraction of the smaller box's area.
  private static func panelOverlapFraction(_ a: PanelRect, _ b: PanelRect) -> Double {
    let smaller = min(area(a), area(b))
    return smaller > 0 ? interArea(a, b) / smaller : 0
  }

  /// Fraction of `panel` covered by `body` — how much the figure dominates that panel.
  private static func coverage(_ body: PanelRect, of panel: PanelRect) -> Double {
    let panelArea = area(panel)
    return panelArea > 0 ? interArea(body, panel) / panelArea : 0
  }

  /// Smallest box covering both inputs.
  private static func union(_ a: PanelRect, _ b: PanelRect) -> PanelRect {
    let x0 = min(a.x, b.x)
    let y0 = min(a.y, b.y)
    let x1 = max(a.x + a.width, b.x + b.width)
    let y1 = max(a.y + a.height, b.y + b.height)
    return PanelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  /// Padded bounding box of a set of rects, clamped to the page. Used for the near-splash zoom rect.
  private static func boundingBox(_ rects: [PanelRect], padding: Double) -> PanelRect {
    let x0 = max(0, (rects.map(\.x).min() ?? 0) - padding)
    let y0 = max(0, (rects.map(\.y).min() ?? 0) - padding)
    let x1 = min(1, (rects.map { $0.x + $0.width }.max() ?? 1) + padding)
    let y1 = min(1, (rects.map { $0.y + $0.height }.max() ?? 1) + padding)
    return PanelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
  }
}
