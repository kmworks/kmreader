//
// ReadingProgressBar.swift
//
//

import SwiftUI

enum ReadingProgressBarType {
  case reader
  case card
}

struct ReadingProgressBar: View {
  let progress: Double
  let height: CGFloat
  let color: Color
  let background: Color
  let showsShadow: Bool
  /// The bottom padding separates the bar from the text block below it;
  /// callers that place nothing below the bar (overlay mode) leave it out.
  let padsBottom: Bool

  @ViewBuilder
  private var progressContent: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(background)
          .frame(height: height)

        Capsule()
          .fill(color)
          .frame(
            width: max(geometry.size.width * progress, progress > 0 ? 4 : 0),
            height: height
          )
          .animation(.appCurve(0.2), value: progress)
      }
    }
  }

  init(progress: Double, type: ReadingProgressBarType, padsBottom: Bool = true) {
    self.progress = progress
    self.height = PlatformHelper.progressBarHeight
    self.padsBottom = padsBottom
    switch type {
    case .reader:
      self.color = .white
      self.background = .secondary.opacity(0.4)
      self.showsShadow = true
    case .card:
      self.color = .primary
      self.background = .secondary.opacity(0.4)
      self.showsShadow = false
    }
  }

  var body: some View {
    Group {
      if showsShadow {
        progressContent
          .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
      } else {
        progressContent
      }
    }
    .frame(height: height)
    .padding(.horizontal, height)
    .padding(.top, height)
    .padding(.bottom, padsBottom ? height : 0)
  }
}
