//
// ReaderLoadingView.swift
//
//

import SwiftUI

struct ReaderLoadingView: View {
  let title: String
  let detail: String
  let progress: Double?
  let cardFill: Color
  let contentColor: Color

  private let contentWidth: CGFloat = 260

  init(
    title: String,
    detail: String,
    progress: Double?,
    cardFill: Color,
    contentColor: Color
  ) {
    self.title = title
    self.detail = detail
    self.progress = progress
    self.cardFill = cardFill
    self.contentColor = contentColor
  }

  private var normalizedProgress: Double? {
    progress.map { min(max($0, 0), 1) }
  }

  private var showsProgress: Bool {
    normalizedProgress != nil
  }

  private var progressText: String {
    (normalizedProgress ?? 0).formatted(.percent.precision(.fractionLength(0)))
  }

  private var numericProgress: Double {
    normalizedProgress ?? 0
  }

  var body: some View {
    VStack(spacing: 20) {
      statusIcon
      textContent
    }
    .frame(width: contentWidth)
    .padding(.vertical, 24)
    .padding(.horizontal, 28)
    .background {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(cardFill)
        .overlay {
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(cardStroke, lineWidth: 0.5)
        }
    }
    .shadow(color: Color.black.opacity(0.12), radius: 30, x: 0, y: 15)
  }

  private var cardStroke: Color {
    contentColor.opacity(0.12)
  }

  private var primaryContentColor: Color {
    contentColor
  }

  private var secondaryContentColor: Color {
    contentColor.opacity(0.72)
  }

  private var progressTrackColor: Color {
    contentColor.opacity(0.14)
  }

  private var statusIcon: some View {
    ZStack {
      Circle()
        .stroke(progressTrackColor, lineWidth: 4)
        .frame(width: 64, height: 64)

      Circle()
        .trim(from: 0, to: normalizedProgress ?? 0)
        .stroke(
          LinearGradient(
            colors: [.primary, .primary.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        .frame(width: 64, height: 64)
        .rotationEffect(.degrees(-90))
        .opacity(showsProgress ? 1 : 0)
        .animation(.appCurve(0.16), value: numericProgress)

      Text(progressText)
        .font(.system(.subheadline, design: .rounded).bold())
        .foregroundStyle(primaryContentColor)
        .monospacedDigit()
        .contentTransition(.numericText(value: numericProgress))
        .animation(.appCurve(0.16), value: numericProgress)
        .opacity(showsProgress ? 1 : 0)
        .accessibilityHidden(!showsProgress)

      LoadingIcon()
        .opacity(showsProgress ? 0 : 1)
        .accessibilityHidden(showsProgress)
    }
    .frame(width: 64, height: 64)
  }

  private var textContent: some View {
    VStack(spacing: 8) {
      titleText
      detailTextView
    }
    .frame(width: contentWidth)
  }

  private var titleText: some View {
    Text(title)
      .font(.headline)
      .foregroundStyle(primaryContentColor)
      .multilineTextAlignment(.center)
      .lineLimit(1)
      .truncationMode(.tail)
      .minimumScaleFactor(0.9)
      .frame(width: contentWidth)
  }

  private var detailTextView: some View {
    Text(detail)
      .font(.subheadline)
      .foregroundStyle(secondaryContentColor)
      .multilineTextAlignment(.center)
      .lineLimit(1)
      .truncationMode(.tail)
      .minimumScaleFactor(0.9)
      .frame(width: contentWidth)
  }
}

#Preview {
  ZStack {
    Color.gray.opacity(0.2).ignoresSafeArea()
    ReaderLoadingView(
      title: "Downloading book...",
      detail: "45% · 12.4 MB / 28.5 MB",
      progress: 0.45,
      cardFill: ReaderBackground.gray.loadingCardFill,
      contentColor: ReaderBackground.gray.loadingContentColor
    )
  }
}
