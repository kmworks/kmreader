//
// TapZoneOverlay.swift
//
//

import SwiftUI

struct TapZoneOverlay: View {
  @Binding var isVisible: Bool
  let readingDirection: ReadingDirection

  @AppStorage("showTapZoneHints") private var showTapZoneHints: Bool = true
  @AppStorage("tapZoneMode") private var tapZoneMode: TapZoneMode = .defaultLayout
  @AppStorage("tapZoneInversionMode") private var tapZoneInversionMode: TapZoneInversionMode = .auto

  private var showsOverlay: Bool {
    isVisible && showTapZoneHints && !tapZoneMode.isDisabled
  }

  var body: some View {
    TapZoneGridOverlayContent(
      tapZoneMode: tapZoneMode,
      tapZoneInversionMode: tapZoneInversionMode,
      readingDirection: readingDirection
    )
    .opacity(showsOverlay ? 1.0 : 0.0)
    .allowsHitTesting(false)
    .animation(.appCurve(), value: showsOverlay)
  }
}

struct TapZoneGridOverlayContent: View {
  let tapZoneMode: TapZoneMode
  let tapZoneInversionMode: TapZoneInversionMode
  let readingDirection: ReadingDirection

  // Representative strip height for the hint overlay / preview only. There is no
  // real page to measure here; runtime tap resolution uses an adaptive fraction.
  private static let tSplitPreviewStripFraction: CGFloat = 0.12

  var body: some View {
    GeometryReader { geometry in
      if tapZoneMode == .tSplit {
        tSplitContent(in: geometry.size)
      } else {
        VStack(spacing: 0) {
          ForEach(0..<3, id: \.self) { row in
            HStack(spacing: 0) {
              ForEach(0..<3, id: \.self) { column in
                Rectangle()
                  .fill(color(row: row, column: column).opacity(0.3))
                  .frame(width: geometry.size.width / 3, height: geometry.size.height / 3)
              }
            }
          }
        }
      }
    }
  }

  // Top strip (controls) + two halves (previous / next). Colours come from the
  // real resolver so the preview always matches runtime resolution, including RTL
  // mirroring; the strip itself does not mirror.
  @ViewBuilder
  private func tSplitContent(in size: CGSize) -> some View {
    let frac = Self.tSplitPreviewStripFraction
    let stripHeight = size.height * frac
    let bodyHeight = size.height - stripHeight
    let bodyY = (1 + frac) / 2
    VStack(spacing: 0) {
      Rectangle()
        .fill(tSplitColor(normalizedX: 0.5, normalizedY: frac / 2).opacity(0.3))
        .frame(width: size.width, height: stripHeight)
      HStack(spacing: 0) {
        Rectangle()
          .fill(tSplitColor(normalizedX: 0.25, normalizedY: bodyY).opacity(0.3))
          .frame(width: size.width / 2, height: bodyHeight)
        Rectangle()
          .fill(tSplitColor(normalizedX: 0.75, normalizedY: bodyY).opacity(0.3))
          .frame(width: size.width / 2, height: bodyHeight)
      }
    }
  }

  private func tSplitColor(normalizedX: CGFloat, normalizedY: CGFloat) -> Color {
    color(
      for: TapZoneHelper.action(
        normalizedX: normalizedX,
        normalizedY: normalizedY,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode,
        readingDirection: readingDirection,
        stripHeightFraction: Self.tSplitPreviewStripFraction
      ))
  }

  private func color(for action: TapZoneAction) -> Color {
    switch action {
    case .previous:
      return .red
    case .next:
      return .green
    case .toggleControls:
      return .blue
    }
  }

  private func color(row: Int, column: Int) -> Color {
    switch TapZoneHelper.action(
      row: row,
      column: column,
      tapZoneMode: tapZoneMode,
      tapZoneInversionMode: tapZoneInversionMode,
      readingDirection: readingDirection
    ) {
    case .previous:
      return .red
    case .next:
      return .green
    case .toggleControls:
      return .blue
    }
  }
}
