//
// PanelOrchestratorDebugHarness.swift
//
//

#if DEBUG
import CoreGraphics
import Foundation

/// Deterministic, runtime check of the orchestrator's cancel / stale-drop behavior.
/// There is no XCTest target, so this is the way to *see* the concurrency invariants
/// hold. Invoke manually, e.g. temporarily from app launch:
///
///     Task { await PanelOrchestratorDebugHarness.run() }
///
/// Prints ✅ / ❌ lines to stdout (visible in the run log). Remove before shipping.
enum PanelOrchestratorDebugHarness {
    /// A loader that returns a fixed synthetic image after a tunable delay, so the
    /// detection path can be cancelled mid-flight on demand.
    private struct FakeLoader: PanelImageLoading {
        let image: CGImage
        let delay: Duration
        func pageImage(bookId: String, page: BookPage) async -> CGImage? {
            try? await Task.sleep(for: delay)
            return image
        }
    }

    static func run() async {
        print("🧪 [PanelHarness] start")
        await staleDropScenario()
        await genuineEmptyScenario()
        await cancelAllScenario()
        print("🧪 [PanelHarness] done")
    }

    // MARK: - Scenarios

    /// Flipping pages mid-detection must NOT cache the cancelled page as a false `.empty`.
    private static func staleDropScenario() async {
        let cache = PanelSequenceCache()
        let provider = StubPanelProvider(latency: .milliseconds(300), isEmptyPage: { _ in false })
        let loader = FakeLoader(image: makeImage(), delay: .milliseconds(50))
        let orchestrator = PanelSequenceOrchestrator(provider: provider, cache: cache, loader: loader)

        let pageA = page(1)
        let pageB = page(2)

        // Start A, then immediately move to B — handlePageChange cancels A.
        orchestrator.prewarm(bookId: book, page: pageA, direction: .ltr)
        orchestrator.handlePageChange(bookId: book, currentPage: pageB, adjacentPages: [], direction: .ltr)

        // Let the cancelled A task fully resolve.
        try? await Task.sleep(for: .milliseconds(600))

        let cachedA = await cache.sequence(for: key(for: pageA, provider: provider).fingerprint)
        if cachedA == nil {
            print("✅ [PanelHarness] stale-drop: cancelled page A left no (false-empty) cache entry")
        } else {
            print("❌ [PanelHarness] stale-drop FAILED: page A cached as \(String(describing: cachedA))")
        }
    }

    /// A genuine `.empty` from a completed detection MUST be cached (and reused).
    private static func genuineEmptyScenario() async {
        let cache = PanelSequenceCache()
        let provider = StubPanelProvider(latency: .milliseconds(10), isEmptyPage: { _ in true })
        let loader = FakeLoader(image: makeImage(), delay: .milliseconds(10))
        let orchestrator = PanelSequenceOrchestrator(provider: provider, cache: cache, loader: loader)

        let pageC = page(5)
        let seq = await orchestrator.sequence(bookId: book, page: pageC, direction: .ltr)
        let cachedC = await cache.sequence(for: key(for: pageC, provider: provider).fingerprint)

        let seqEmpty = seq == .empty
        let cachedEmpty: Bool = { if case .empty? = cachedC { return true } else { return false } }()
        if seqEmpty && cachedEmpty {
            print("✅ [PanelHarness] genuine empty: result and cache are both .empty")
        } else {
            print("❌ [PanelHarness] genuine-empty FAILED: seq=\(String(describing: seq)) cached=\(String(describing: cachedC))")
        }
    }

    /// `cancelAll` must drop every in-flight task.
    private static func cancelAllScenario() async {
        let cache = PanelSequenceCache()
        let provider = StubPanelProvider(latency: .milliseconds(300), isEmptyPage: { _ in false })
        let loader = FakeLoader(image: makeImage(), delay: .milliseconds(50))
        let orchestrator = PanelSequenceOrchestrator(provider: provider, cache: cache, loader: loader)

        orchestrator.prewarm(bookId: book, page: page(1), direction: .ltr)
        orchestrator.prewarm(bookId: book, page: page(2), direction: .ltr)
        orchestrator.cancelAll()

        if orchestrator.inFlightCount == 0 {
            print("✅ [PanelHarness] cancelAll: no in-flight tasks remain")
        } else {
            print("❌ [PanelHarness] cancelAll FAILED: \(orchestrator.inFlightCount) in-flight")
        }
    }

    // MARK: - Fixtures

    private static let book = "harness-book"

    private static func page(_ number: Int) -> BookPage {
        BookPage(
            number: number,
            fileName: "page-\(number).jpg",
            mediaType: "image/jpeg",
            width: 800,
            height: 1200,
            sizeBytes: Int64(10_000 + number),
            size: "",
            downloadURL: nil
        )
    }

    private static func key(for page: BookPage, provider: any PanelDetectionProvider) -> PanelCacheKey {
        PanelCacheKey(
            instanceId: CacheNamespace.identifier(),
            bookId: book,
            page: page,
            detectorVersion: provider.version,
            direction: .ltr
        )
    }

    /// Portrait synthetic image (height > width) so the default stub treats it as paneled.
    private static func makeImage(width: Int = 4, height: Int = 8) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        return context!.makeImage()!
    }
}
#endif
