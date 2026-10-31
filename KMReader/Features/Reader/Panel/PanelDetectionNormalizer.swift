//
// PanelDetectionNormalizer.swift
//
// Detector-agnostic post-detection cleanup applied to any provider's raw boxes:
// confidence-aware overlap suppression (IoU or low-confidence containment), then a lone
// whole-page box collapses to "no panels" so the reader shows the whole page. Holds no
// detector or networking specifics, so every provider reuses it.
//

import Foundation

/// One raw detector candidate: a normalized `[0,1]` box plus its confidence. Confidence is
/// kept only long enough for suppression; it never crosses into the reader contract.
struct RawPanel: Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Double
}

/// Confidence-aware suppression + lone-whole-page collapse, shared by every detection provider.
nonisolated enum PanelDetectionNormalizer {
    /// Two boxes overlapping past this IoU → drop the lower-confidence one.
    static let nmsIoU: Double = 0.5
    /// A box covered this much by a kept box (fraction of its OWN area) is a redundant
    /// wrapper/split candidate ...
    static let selfCover: Double = 0.7
    /// ... but only dropped if it is also below this confidence, so legit high-confidence
    /// panels are never removed.
    static let coverConf: Double = 0.6
    /// A lone box whose width OR height reaches this fraction of the page is the whole page.
    static let fullPageFraction: Double = 0.95
    /// A box covering at least this fraction of the page area, alongside other panels, is treated
    /// as a spurious page-spanning detection (region detectors emit these) — but only when it is
    /// also below `nearFullPageConf`, so a real high-confidence establishing panel is never dropped.
    static let nearFullPageArea: Double = 0.85
    static let nearFullPageConf: Double = 0.5

    /// Greedy descending-confidence suppression followed by the lone-whole-page collapse.
    /// Input is the raw frame-class boxes (already confidence-thresholded); output is the kept
    /// panels with confidence dropped, in detection order (the reading-order layer sorts them).
    static func normalize(_ candidates: [RawPanel]) -> [PanelRect] {
        var kept: [RawPanel] = []
        for p in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            let pArea = p.width * p.height
            var drop = false
            for k in kept {
                let (inter, iou) = overlap(p, k)
                let selfCov = pArea > 0 ? inter / pArea : 0
                if iou >= nmsIoU || (selfCov >= selfCover && p.confidence < coverConf) {
                    drop = true
                    break
                }
            }
            if !drop { kept.append(p) }
        }

        // A low-confidence near-full-page box alongside smaller panels defeats column/row cuts
        // and adds a spurious step — drop it (region detectors emit these on busy pages).
        if kept.count > 1 {
            kept.removeAll { $0.width * $0.height >= nearFullPageArea && $0.confidence < nearFullPageConf }
        }

        // A lone whole-page box (splash / single artwork) → no panels.
        if kept.count == 1,
           kept[0].width >= fullPageFraction || kept[0].height >= fullPageFraction {
            return []
        }

        return kept.map { PanelRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    }

    /// IoU-only dedup for the non-panel classes (text/body). Greedy descending-confidence
    /// suppression of near-duplicate boxes, without any of the panel-specific rules (no
    /// wrapper/containment drop, no whole-page collapse) — those carry panel semantics that do
    /// not apply to bubbles or figures, which legitimately sit inside panels and beside each other.
    static func dedupe(_ candidates: [RawPanel]) -> [PanelRect] {
        var kept: [RawPanel] = []
        for p in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            if kept.contains(where: { overlap(p, $0).iou >= nmsIoU }) { continue }
            kept.append(p)
        }
        return kept.map { PanelRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    }

    /// Intersection area and IoU of two normalized boxes.
    private static func overlap(_ a: RawPanel, _ b: RawPanel) -> (inter: Double, iou: Double) {
        let iw = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
        let ih = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
        let inter = iw * ih
        let union = a.width * a.height + b.width * b.height - inter
        return (inter, union > 0 ? inter / union : 0)
    }
}
