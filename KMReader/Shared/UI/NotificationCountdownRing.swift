//
// NotificationCountdownRing.swift
//
//

import SwiftUI

/// Remaining lifetime of an action toast as a thin depleting ring around the
/// seconds count (Telegram secretTimeout style): communicates that the window
/// is closing without a bare readout sitting between message and button.
struct NotificationCountdownRing: View {
  let deadline: Date
  let lifetime: TimeInterval

  var body: some View {
    TimelineView(.animation) { context in
      let remaining = max(0, deadline.timeIntervalSince(context.date))
      let fraction = lifetime > 0 ? remaining / lifetime : 0
      ZStack {
        Circle()
          .stroke(Color.secondary.opacity(0.25), lineWidth: 1.75)
        Circle()
          .trim(from: 0, to: fraction)
          .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text(verbatim: "\(Int(ceil(remaining)))")
          .font(.system(size: 9, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
          .animation(.appCurve(0.2), value: Int(ceil(remaining)))
      }
      .frame(width: 16, height: 16)
    }
  }
}
