//
// StubPanelProvider.swift
//
//

import CoreGraphics
import Foundation

/// Deterministic stub conforming to PanelDetectionProvider.
/// Returns a synthetic 2×3 panel grid (mirrored for RTL); landscape images return .empty.
/// Sleeps for `latency` before returning so callers can exercise cancellation and stale-drop.
struct StubPanelProvider: PanelDetectionProvider {
    let latency: Duration
    let isEmptyPage: @Sendable (CGImage) -> Bool

    /// - Parameters:
    ///   - latency: Artificial delay before every result. Default 200 ms.
    ///   - isEmptyPage: Predicate that selects which images return `.empty`.
    ///     Default: landscape (width ≥ height) — mirrors real-world spreads/splashes.
    init(
        latency: Duration = .milliseconds(200),
        isEmptyPage: @Sendable @escaping (CGImage) -> Bool = { $0.width >= $0.height }
    ) {
        self.latency = latency
        self.isEmptyPage = isEmptyPage
    }

    var version: String { "stub-1.0" }

    nonisolated func detect(image: CGImage) async -> PageDetection {
        do {
            try await Task.sleep(for: latency)
        } catch {
            return .empty
        }
        guard !isEmptyPage(image) else { return .empty }
        return PageDetection(panels: panelGrid(), texts: [], bodies: [])
    }

    // MARK: - Private

    /// A synthetic 2×3 grid in natural order; `PanelComposition` applies reading order per direction.
    private nonisolated func panelGrid() -> [PanelRect] {
        let cols = 2
        let rows = 3
        let w = 1.0 / Double(cols)
        let h = 1.0 / Double(rows)

        var grid: [PanelRect] = []
        for row in 0..<rows {
            for col in 0..<cols {
                grid.append(PanelRect(x: Double(col) * w, y: Double(row) * h, width: w, height: h))
            }
        }
        return grid
    }
}
