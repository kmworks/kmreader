//
// ProgressTween.swift
//
//

import Foundation

/// Tween tuning shared by the platform CircularProgressView branches: small steps
/// advance quickly; larger jumps stretch towards ~0.65s so they read smooth
/// instead of twitching.
enum ProgressTween {
  static func duration(forDelta delta: Double) -> TimeInterval {
    guard delta > 0.25 else { return 0.2 }
    return 0.2 + min(0.45, 0.45 * (delta - 0.25) * 5)
  }

  static func easeOutCubic(_ t: Double) -> Double {
    1 - pow(1 - t, 3)
  }
}
