//
//  Animation+App.swift
//
//

import SwiftUI

extension Animation {
  /// Standard quick-UI curve; use instead of easeInOut for short transitions.
  static func appCurve(_ duration: Double = 0.25) -> Animation {
    .timingCurve(0.38, 0.7, 0.125, 1.0, duration: duration)
  }

  /// Overdamped spring; use for motion that gestures can interrupt so velocity is inherited.
  static var appSpring: Animation {
    .spring(duration: 0.4, bounce: 0)
  }
}
