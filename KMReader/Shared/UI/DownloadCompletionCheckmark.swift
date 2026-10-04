//
// DownloadCompletionCheckmark.swift
//
//

import SwiftUI

/// Transient drawn checkmark celebrating a finished download: strokes in while the
/// glyph settles with a 1.0 → 0.9 → 1.1 → 1.0 bounce.
struct DownloadCompletionCheckmark: View {
  let progress: Double
  let color: Color
  let bounceTrigger: Int

  var body: some View {
    KeyframeAnimator(initialValue: 1.0, trigger: bounceTrigger) { scale in
      DownloadCompletionCheckmarkShape(progress: progress)
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .scaleEffect(scale)
    } keyframes: { _ in
      KeyframeTrack(\.self) {
        LinearKeyframe(0.9, duration: 0.08)
        LinearKeyframe(1.1, duration: 0.13)
        LinearKeyframe(1.0, duration: 0.1)
      }
    }
  }
}
