//
// DownloadCompletionCheckmarkShape.swift
//
//

import SwiftUI

/// Two-stroke checkmark drawn progressively: the short arm takes the first third of
/// the progress, the long arm the rest, so a linear 0→1 animation reads as one motion.
nonisolated struct DownloadCompletionCheckmarkShape: Shape {
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    // The settled state is the smaller check inside checkmark.icloud.fill, so the
    // drawn check stays well inside the icon frame to soften the swap.
    let rect = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.2)
    let start = CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY)
    let corner = CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12)
    let end = CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY + rect.height * 0.15)

    var path = Path()
    let shortArm = min(progress * 3, 1)
    guard shortArm > 0 else { return path }
    path.move(to: start)
    path.addLine(
      to: CGPoint(
        x: start.x + (corner.x - start.x) * shortArm,
        y: start.y + (corner.y - start.y) * shortArm))
    let longArm = max((progress - 1.0 / 3.0) * 1.5, 0)
    if longArm > 0 {
      path.addLine(
        to: CGPoint(
          x: corner.x + (end.x - corner.x) * longArm,
          y: corner.y + (end.y - corner.y) * longArm))
    }
    return path
  }
}
