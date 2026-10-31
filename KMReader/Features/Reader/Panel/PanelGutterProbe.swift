//
// PanelGutterProbe.swift
//
// Pixel evidence for the reading-order X-Y cut: box projections cannot tell a real gutter
// from a coincidental gap forced through drawn ink, but the page raster can. A candidate
// cut is classified by whether an unbroken background corridor crosses its band strip:
//   - `line`: a corridor confined to a narrow window — one straight(-ish) perceptual
//     boundary, the strongest evidence;
//   - `path`: a corridor that wanders across the band (slanted or staircase gutters) —
//     real separation, but weaker structure;
//   - `phantom`: every crossing is walled off by ink — the cut only exists because box
//     tolerance forgave a real overlap, and taking it would fragment the layout.
// The corridor may cross a few thin strokes (a bubble outline spilling over a real gutter)
// but not ink in bulk, and it may never tunnel through a detected box's interior — a flat
// white region inside a panel is content, not gutter.
//

import Foundation

nonisolated enum PanelGutterProbe {
    enum Verdict: Int, Comparable {
        case phantom = 0
        case path = 1
        case line = 2

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Axis {
        /// Horizontal cut: the band is a range of rows, the corridor runs left-to-right.
        case horizontal
        /// Vertical cut: the band is a range of columns, the corridor runs top-to-bottom.
        case vertical
    }

    /// Band expansion beyond the box-edge interval, absorbing detection-box bleed.
    static let bandPadding = 0.012
    /// Detected boxes shrunk by this much still block the corridor: no tunneling through a
    /// panel's flat interior, while the bleed zone just inside a box edge stays passable.
    static let boxErosion = 0.02
    /// Total non-background cells a corridor may cross (two or three thin strokes).
    static let maxCrossingCost = 14
    /// A corridor confined to a window this many cells thick still counts as `line`.
    static let lineWindow = 16
    /// Spans (cells along the corridor) below this are too short to judge: accept as `line`.
    static let minSpanCells = 18
    /// Bands (cells across the corridor) below this are too thin to judge: accept as `line`.
    static let minBandCells = 4

    /// Classify a candidate cut. `loEdge`/`hiEdge` bound the claimed gutter on the cut axis
    /// (they may be inverted when boxes overlap; the whole overlap zone is probed either
    /// way). `spanLo`/`spanHi` bound the corridor on the other axis. `boxes` are the
    /// region's rects, whose eroded interiors block the corridor. All coordinates
    /// normalized to [0, 1].
    static func rank(
        raster: PanelPageRaster, boxes: [PanelRect], axis: Axis,
        loEdge: Double, hiEdge: Double, spanLo: Double, spanHi: Double
    ) -> Verdict {
        let lineCells = axis == .horizontal ? raster.height : raster.width
        let spanCells = axis == .horizontal ? raster.width : raster.height
        let b0 = min(loEdge, hiEdge) - bandPadding
        let b1 = max(loEdge, hiEdge) + bandPadding
        let i0 = max(0, Int((b0 * Double(lineCells)).rounded(.down)))
        let i1 = min(lineCells - 1, Int((b1 * Double(lineCells)).rounded(.up)))
        let s0 = max(0, Int((spanLo * Double(spanCells)).rounded(.down)))
        let s1 = min(spanCells, Int((spanHi * Double(spanCells)).rounded(.up)))
        let bandHeight = i1 - i0 + 1
        let spanLength = s1 - s0
        guard spanLength >= minSpanCells, bandHeight >= minBandCells else { return .line }

        // Strip costs, row-major `bandHeight x spanLength`: 0 = background, 1 = crossing.
        var cost = [Int](repeating: 1, count: bandHeight * spanLength)
        for r in 0..<bandHeight {
            for c in 0..<spanLength {
                let x = axis == .horizontal ? s0 + c : i0 + r
                let y = axis == .horizontal ? i0 + r : s0 + c
                if raster.background[y * raster.width + x] { cost[r * spanLength + c] = 0 }
            }
        }
        for box in boxes {
            let e = (x0: box.x + boxErosion, y0: box.y + boxErosion,
                     x1: box.x + box.width - boxErosion, y1: box.y + box.height - boxErosion)
            guard e.x1 > e.x0, e.y1 > e.y0 else { continue }
            let (lo, hi, cLo, cHi) = axis == .horizontal
                ? (e.y0, e.y1, e.x0, e.x1)
                : (e.x0, e.x1, e.y0, e.y1)
            let r0 = max(0, Int((lo * Double(lineCells)).rounded(.down)) - i0)
            let r1 = min(bandHeight, Int((hi * Double(lineCells)).rounded(.up)) - i0)
            let c0 = max(0, Int((cLo * Double(spanCells)).rounded(.down)) - s0)
            let c1 = min(spanLength, Int((cHi * Double(spanCells)).rounded(.up)) - s0)
            guard r1 > r0, c1 > c0 else { continue }
            for r in r0..<r1 {
                for c in c0..<c1 { cost[r * spanLength + c] = 1 }
            }
        }

        // Straight line: the cheapest single band row.
        var bestLine = Int.max
        for r in 0..<bandHeight {
            var sum = 0
            for c in 0..<spanLength { sum += cost[r * spanLength + c] }
            bestLine = min(bestLine, sum)
        }
        if bestLine <= maxCrossingCost { return .line }

        // Windowed path: wandering confined to a narrow window is still one boundary.
        // A band no thicker than the window is itself narrow, so its path verdict is `line`.
        guard bandHeight > lineWindow else {
            return pathCost(cost, rows: 0..<bandHeight, span: spanLength) <= maxCrossingCost
                ? .line : .phantom
        }
        let step = lineWindow / 2
        var start = 0
        while start + lineWindow <= bandHeight {
            if pathCost(cost, rows: start..<(start + lineWindow), span: spanLength) <= maxCrossingCost {
                return .line
            }
            start += step
        }

        // Free path across the whole band.
        return pathCost(cost, rows: 0..<bandHeight, span: spanLength) <= maxCrossingCost
            ? .path : .phantom
    }

    /// Minimum total cost of a span-monotone path from the first to the last span column,
    /// moving freely up and down within a column and paying every cell it enters.
    private static func pathCost(_ cost: [Int], rows: Range<Int>, span: Int) -> Int {
        let h = rows.count
        var d = [Int](repeating: 0, count: h)
        var col = [Int](repeating: 0, count: h)
        for c in 0..<span {
            for (k, r) in rows.enumerated() { col[k] = cost[r * span + c] }
            if c == 0 {
                for k in 0..<h { d[k] = col[k] }
            } else {
                for k in 0..<h { d[k] += col[k] }
            }
            if h > 1 {
                for k in 1..<h { d[k] = min(d[k], d[k - 1] + col[k]) }
                for k in stride(from: h - 2, through: 0, by: -1) { d[k] = min(d[k], d[k + 1] + col[k]) }
            }
        }
        return d.min() ?? 0
    }
}
