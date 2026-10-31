//
// PanelReadingOrder.swift
//
// Detector-agnostic reading-order layer. Takes unordered normalized panel rects
// and returns them in manga/comic reading order via a recursive X-Y cut. This is
// the one piece shared by every detection provider, so it contains NO detector or
// networking specifics.
//

import CoreGraphics
import Foundation

/// Recursive X-Y cut panel ordering, raster-verified when the page pixels are available.
///
/// At each level every core-gap candidate on both axes is collected and classified by the
/// gutter probe (`PanelGutterProbe`): a cut is only trusted when an unbroken background
/// corridor actually crosses the page there. The strongest verdict wins — a straight
/// corridor beats a wandering one, horizontal beats vertical, wider gap breaks ties — so a
/// coincidental box gap forced through drawn ink (which would fragment a column) loses to
/// a clean gutter on the other axis. A wandering corridor supports a vertical cut only
/// when the horizontal axis has no candidate at all: rows dominate comic layout, and a
/// zig-zag column boundary against even a forced row boundary is usually two stitched
/// gutters, not a real column. When every candidate is phantom (a fully ink-bridged
/// boundary) the widest horizontal candidate is taken as before — the probe refuses to
/// invent new structure where the boxes see some. Without a raster every candidate ranks
/// as a straight corridor and the behavior is the classic X-Y cut.
///
/// Pages with no cut candidate fall back to a deterministic constraint-graph order,
/// keeping the result stable and independent of input order even when the layout is
/// genuinely ambiguous.
///
/// The cut is generic over any element that can yield a rect, so the same algorithm
/// orders bare `PanelRect`s and tagged items (panels interleaved with orphan figures)
/// identically — the `[PanelRect]` entry point is just the identity accessor.
nonisolated enum PanelReadingOrder {
    /// Minimum normalized gap that counts as a real cut. Keeps thin inter-panel art
    /// lines from triggering spurious splits.
    static let defaultGutter: Double = 0.015
    /// Normalized slack so a panel whose detection box bleeds slightly past a gutter does not
    /// block an otherwise-clean cut: each edge is pulled in by this much before the gap is
    /// tested, so a small overhang is forgiven instead of defeating the cut and dropping the
    /// page to the less-accurate banded fallback. At 0.04 a tall side panel spanning the page height,
    /// beside a column of smaller panels whose boxes poke slightly past the gutter, still resolves to a
    /// clean column split, so that column reads first in RTL instead of dropping to the fallback.
    static let defaultOverlapTolerance: Double = 0.04
    /// No-clean-cut fallback thresholds (see `fallbackSorted`). `fallbackRowOverlap` is the vertical-overlap
    /// fraction (of the shorter box) above which two panels are confidently the same row — and, applied on the
    /// x-axis, a confident column. Half-height is the natural split: a full-column panel overlaps every panel
    /// beside it by at least half their height.
    static let fallbackRowOverlap: Double = 0.5
    /// Below this vertical-overlap fraction a side-by-side pair is not entangled enough to attach as neighbors
    /// on box evidence alone; with a raster, the gutter probe arbitrates such pairs instead (`pairCorridor`).
    static let fallbackAttachOverlap: Double = 0.25
    /// Rectangle interpenetration (min-axis) up to which an overlap is attributed to detector bleed rather than a
    /// real stack; above it an overlapping pair is treated as genuinely stacked (top before bottom).
    static let fallbackBleedDepth: Double = 0.038
    /// Max horizontal gap (negative = overlap) at which two side-by-side boxes still count as in contact.
    static let fallbackContactGap: Double = 0.02
    /// A box contained in another but starting within this distance of the container's top edge is an
    /// L-shaped panel's bounding box wrapping a same-row neighbor, not a true inset (which starts deep
    /// inside its container): the pair still reads as side-by-side.
    static let containedHugMargin: Double = 0.03

    /// Order normalized panel rects in reading order.
    static func ordered(
        _ rects: [PanelRect],
        direction: ReadingDirection,
        gutter: Double = defaultGutter,
        overlapTolerance: Double = defaultOverlapTolerance,
        raster: PanelPageRaster? = nil
    ) -> [PanelRect] {
        ordered(rects, rect: { $0 }, direction: direction,
                gutter: gutter, overlapTolerance: overlapTolerance, raster: raster)
    }

    /// Order arbitrary items by the reading order of their rects. Used to interleave panels with
    /// orphan-figure beats: both move through the same X-Y cut, so an unbounded figure lands in its
    /// geometric reading slot among the panels.
    static func ordered<T>(
        _ items: [T],
        rect: (T) -> PanelRect,
        direction: ReadingDirection,
        gutter: Double = defaultGutter,
        overlapTolerance: Double = defaultOverlapTolerance,
        raster: PanelPageRaster? = nil
    ) -> [T] {
        guard items.count > 1 else { return items }

        let horizontal = axisCandidates(
            items, rect: rect, axis: .horizontal, gutter: gutter, tolerance: overlapTolerance, raster: raster)
        let vertical = axisCandidates(
            items, rect: rect, axis: .vertical, gutter: gutter, tolerance: overlapTolerance, raster: raster)

        // Strongest verdict first, horizontal before vertical, widest core gap within a tie.
        // A wandering corridor may back a vertical cut only when no horizontal candidate exists.
        var best: (key: (Int, Int, Double), axis: PanelGutterProbe.Axis, candidate: Candidate<T>)?
        for (axis, priority, candidates) in [
            (PanelGutterProbe.Axis.horizontal, 1, horizontal),
            (PanelGutterProbe.Axis.vertical, 0, vertical),
        ] {
            for candidate in candidates where candidate.rank != .phantom {
                if axis == .vertical, candidate.rank == .path, !horizontal.isEmpty { continue }
                let key = (candidate.rank.rawValue, priority, candidate.coreGap)
                if best == nil || key > best!.key { best = (key, axis, candidate) }
            }
        }
        // Every candidate phantom: a fully ink-bridged boundary. Take the widest horizontal
        // (then vertical) as the raster-less algorithm would, instead of inventing structure.
        if best == nil {
            for (axis, candidates) in [
                (PanelGutterProbe.Axis.horizontal, horizontal), (PanelGutterProbe.Axis.vertical, vertical),
            ] {
                guard var widest = candidates.first else { continue }
                for candidate in candidates.dropFirst() where candidate.coreGap > widest.coreGap {
                    widest = candidate
                }
                best = ((0, 0, widest.coreGap), axis, widest)
                break
            }
        }

        if let (_, axis, candidate) = best {
            var first = Array(candidate.sorted[..<candidate.splitIndex])
            var second = Array(candidate.sorted[candidate.splitIndex...])
            if axis == .vertical, direction == .rtl { swap(&first, &second) }
            return ordered(first, rect: rect, direction: direction,
                           gutter: gutter, overlapTolerance: overlapTolerance, raster: raster)
                + ordered(second, rect: rect, direction: direction,
                          gutter: gutter, overlapTolerance: overlapTolerance, raster: raster)
        }

        return fallbackSorted(items, rect: rect, direction: direction, raster: raster)
    }

    // MARK: - Cut candidates

    private struct Candidate<T> {
        let rank: PanelGutterProbe.Verdict
        let coreGap: Double
        let sorted: [T]
        let splitIndex: Int
    }

    /// Every split position on one axis whose core gap (edges pulled in by the tolerance)
    /// reaches the gutter, each classified by the raster probe. Phantom candidates are kept
    /// for the all-phantom fallback. Without a raster everything ranks `.line`.
    private static func axisCandidates<T>(
        _ items: [T],
        rect: (T) -> PanelRect,
        axis: PanelGutterProbe.Axis,
        gutter: Double,
        tolerance: Double,
        raster: PanelPageRaster?
    ) -> [Candidate<T>] {
        guard items.count > 1 else { return [] }
        func lo(_ r: PanelRect) -> Double { axis == .horizontal ? r.y : r.x }
        func hi(_ r: PanelRect) -> Double { axis == .horizontal ? r.y + r.height : r.x + r.width }
        func spanLo(_ r: PanelRect) -> Double { axis == .horizontal ? r.x : r.y }
        func spanHi(_ r: PanelRect) -> Double { axis == .horizontal ? r.x + r.width : r.y + r.height }

        let sorted = items.sorted { lo(rect($0)) < lo(rect($1)) }
        let boxes = sorted.map(rect)
        let regionSpanLo = boxes.map(spanLo).min() ?? 0
        let regionSpanHi = boxes.map(spanHi).max() ?? 1

        var candidates: [Candidate<T>] = []
        var maxCoreHi = -Double.infinity
        var maxRawHi = -Double.infinity
        for i in sorted.indices {
            if i > 0 {
                let gap = (lo(boxes[i]) + tolerance) - maxCoreHi
                if gap >= gutter {
                    let rank = raster.map {
                        PanelGutterProbe.rank(
                            raster: $0, boxes: boxes, axis: axis,
                            loEdge: maxRawHi, hiEdge: lo(boxes[i]),
                            spanLo: regionSpanLo, spanHi: regionSpanHi)
                    } ?? .line
                    candidates.append(Candidate(rank: rank, coreGap: gap, sorted: sorted, splitIndex: i))
                }
            }
            maxCoreHi = max(maxCoreHi, hi(boxes[i]) - tolerance)
            maxRawHi = max(maxRawHi, hi(boxes[i]))
        }
        return candidates
    }

    // MARK: - Fallback

    /// Deterministic order for items with no cut candidate (borderless art, or overlapping boxes where
    /// neither a row nor a column gutter exists). Builds a constraint graph from the *confident*
    /// pairwise relations only and resolves it with a topological sort:
    ///   - deeply entangled on both axes (row AND column overlap above `fallbackRowOverlap`): an inset
    ///     or an overlaid panel — top before bottom, unless the smaller box protrudes sideways or hugs
    ///     the container's top edge (`readsBeside`), which is side-by-side geometry: reading axis;
    ///   - same row (vertical overlap >= `fallbackRowOverlap` of the shorter): read along the reading axis;
    ///   - same column (horizontal overlap >= `fallbackRowOverlap`): read top before bottom;
    ///   - genuinely stacked (rectangle interpenetration > `fallbackBleedDepth`, beyond detector bleed): top
    ///     before bottom;
    ///   - side-by-side in horizontal contact (entangled vertically, barely x-separated): reading axis;
    ///   - below the attach threshold but touching, with a raster: the gutter probe arbitrates — a
    ///     confirmed background corridor between the facing edges means genuinely side-by-side (this
    ///     replaces trusting a knife-edge overlap threshold with pixel evidence).
    /// Ambiguous pairs get no edge; transitivity through neighbors resolves them. The ready set is broken by a
    /// total key (top edge, then reading axis, then original index), so unlike a pairwise comparator the result
    /// can never depend on input order — the classic cause of the same layout ordering differently as detector
    /// boxes jitter. A guard breaks any residual cycle on pathological pinwheel layouts.
    private static func fallbackSorted<T>(
        _ items: [T],
        rect: (T) -> PanelRect,
        direction: ReadingDirection,
        raster: PanelPageRaster?
    ) -> [T] {
        let n = items.count
        let r = items.map(rect)

        func midX(_ b: PanelRect) -> Double { b.x + b.width / 2 }
        func midY(_ b: PanelRect) -> Double { b.y + b.height / 2 }
        func yOverlap(_ a: PanelRect, _ b: PanelRect) -> Double {
            max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
        }
        func xOverlap(_ a: PanelRect, _ b: PanelRect) -> Double {
            max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
        }
        // rectangle interpenetration depth (min axis), 0 unless the boxes overlap in both axes
        func penetration(_ a: PanelRect, _ b: PanelRect) -> Double {
            let ox = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
            let oy = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
            return (ox > 0 && oy > 0) ? min(ox, oy) : 0
        }
        // horizontal gap between two boxes; negative means they overlap in x
        func horizontalGap(_ a: PanelRect, _ b: PanelRect) -> Double {
            max(a.x, b.x) - min(a.x + a.width, b.x + b.width)
        }
        // true if a reads before b once they are known to share a reading axis
        func readingFirst(_ a: PanelRect, _ b: PanelRect) -> Bool {
            if midX(a) != midX(b) { return direction == .rtl ? midX(a) > midX(b) : midX(a) < midX(b) }
            return midY(a) < midY(b)
        }

        // edges[i][j] == true means i reads before j
        var edges = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        var indegree = [Int](repeating: 0, count: n)
        func addEdge(_ i: Int, _ j: Int) {
            if !edges[i][j] { edges[i][j] = true; indegree[j] += 1 }
        }
        func addReadingEdge(_ i: Int, _ j: Int) {
            if readingFirst(r[i], r[j]) { addEdge(i, j) } else { addEdge(j, i) }
        }
        func addTopEdge(_ i: Int, _ j: Int) {
            if midY(r[i]) != midY(r[j]) {
                let up = midY(r[i]) < midY(r[j]) ? i : j
                addEdge(up, up == i ? j : i)
            }
        }
        for i in 0..<n {
            for j in (i + 1)..<n {
                let a = r[i], b = r[j]
                let shorterH = max(.leastNonzeroMagnitude, min(a.height, b.height))
                let shorterW = max(.leastNonzeroMagnitude, min(a.width, b.width))
                let yr = yOverlap(a, b) / shorterH
                let xr = xOverlap(a, b) / shorterW
                if yr >= fallbackRowOverlap, xr >= fallbackRowOverlap, !readsBeside(a, b) {
                    addTopEdge(i, j)                                        // inset / overlaid panel
                } else if yr >= fallbackRowOverlap {                        // confident same row
                    addReadingEdge(i, j)
                } else if xr >= fallbackRowOverlap {                        // confident same column
                    addTopEdge(i, j)
                } else if penetration(a, b) > fallbackBleedDepth, yOverlap(a, b) > 0 {   // genuinely stacked
                    addTopEdge(i, j)
                } else if yr >= fallbackAttachOverlap, xr < fallbackRowOverlap,
                          horizontalGap(a, b) < fallbackContactGap {        // side-by-side in contact
                    addReadingEdge(i, j)
                } else if let raster, yr > 0, yr < fallbackAttachOverlap, xr < fallbackRowOverlap,
                          horizontalGap(a, b) < fallbackContactGap,
                          pairCorridor(raster: raster, a, b) {              // raster-confirmed neighbors
                    addReadingEdge(i, j)
                }
                // else: ambiguous pair, no edge
            }
        }

        // total ordering key for the ready set: topmost edge, then reading axis, then original index
        func readyPrecedes(_ i: Int, _ j: Int) -> Bool {
            let a = r[i], b = r[j]
            if a.y != b.y { return a.y < b.y }
            let ai = direction == .rtl ? -midX(a) : midX(a)
            let bi = direction == .rtl ? -midX(b) : midX(b)
            if ai != bi { return ai < bi }
            return i < j
        }

        var remaining = Set(0..<n)
        var result = [T]()
        result.reserveCapacity(n)
        while !remaining.isEmpty {
            var ready = remaining.filter { indegree[$0] == 0 }
            if ready.isEmpty { ready = remaining }                              // cycle guard
            let pick = ready.min(by: readyPrecedes)!
            result.append(items[pick])
            remaining.remove(pick)
            for j in 0..<n where edges[pick][j] {
                edges[pick][j] = false
                indegree[j] -= 1
            }
        }
        return result
    }

    /// Classify a deeply two-axis-entangled pair as side-by-side rather than stacked/inset. The
    /// smaller box's protrusion outside the bigger tells the relation axis: poking out sideways
    /// means beside, poking out vertically means stacked. Fully contained is a true inset (reads
    /// by height) unless it hugs the container's top edge — an L-shaped panel's bounding box
    /// wrapping a same-row neighbor.
    private static func readsBeside(_ a: PanelRect, _ b: PanelRect) -> Bool {
        let (small, big) = a.width * a.height <= b.width * b.height ? (a, b) : (b, a)
        let px = max(0, big.x - small.x, small.x + small.width - big.x - big.width)
        let py = max(0, big.y - small.y, small.y + small.height - big.y - big.height)
        if px == 0, py == 0 { return small.y - big.y < containedHugMargin }
        return px > py
    }

    /// Raster-confirmed vertical background corridor between the facing edges of two boxes.
    private static func pairCorridor(raster: PanelPageRaster, _ a: PanelRect, _ b: PanelRect) -> Bool {
        let (left, right) = a.x + a.width / 2 <= b.x + b.width / 2 ? (a, b) : (b, a)
        return PanelGutterProbe.rank(
            raster: raster, boxes: [a, b], axis: .vertical,
            loEdge: left.x + left.width, hiEdge: right.x,
            spanLo: max(a.y, b.y), spanHi: min(a.y + a.height, b.y + b.height)
        ) != .phantom
    }
}
