import Foundation

struct ReaderPreloadWindow: Equatable, Sendable {
  let preloadBefore: Int
  let preloadAfter: Int
  let keepRangeBefore: Int
  let keepRangeAfter: Int

  // Window values are the effective preload reach: preloadPages uses them as
  // is. Forward reach must cover the next dual-page spread: the spread partner
  // sits at current+1 and the next spread at current+2/+3, so anything less
  // leaves tap turns landing on a cold spread. Balanced and Fast also cover
  // the previous spread backward (current-3 in the LTR worst case). Low
  // Memory deliberately trades that for memory: its backward reach is one
  // page, so backward dual-page turns may briefly load. keepRange must stay
  // >= the preload window or freshly preloaded pages would be evicted
  // immediately; the larger profiles keep a margin beyond it so quick flips
  // back stay warm at no extra decode cost.
  static let lowMemory = ReaderPreloadWindow(
    preloadBefore: 1,
    preloadAfter: 3,
    keepRangeBefore: 1,
    keepRangeAfter: 3
  )

  static let balanced = ReaderPreloadWindow(
    preloadBefore: 3,
    preloadAfter: 5,
    keepRangeBefore: 5,
    keepRangeAfter: 7
  )

  static let fastPageTurns = ReaderPreloadWindow(
    preloadBefore: 5,
    preloadAfter: 7,
    keepRangeBefore: 7,
    keepRangeAfter: 9
  )
}
