//
// ShimmerClock.swift
//
//

import SwiftUI

/// Shared sweep phase for every shimmer placeholder, so all visible skeletons
/// highlight in lockstep instead of each running its own repeatForever. The
/// clock is animation-driven: the first visible placeholder starts a repeating
/// animation on `phase` and the last one stops it, so off-screen skeletons
/// cost nothing. Views appearing mid-cycle read the same value and join in
/// sync.
@MainActor
@Observable
final class ShimmerClock {
  static let shared = ShimmerClock()

  static let period: Double = 1.3

  private(set) var phase: Double = 0

  private var retainCount = 0

  func retain() {
    retainCount += 1
    guard retainCount == 1 else { return }
    withAnimation(.appCurve(Self.period).repeatForever(autoreverses: false)) {
      phase = 1
    }
  }

  func release() {
    retainCount = max(0, retainCount - 1)
    guard retainCount == 0 else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      phase = 0
    }
  }
}
