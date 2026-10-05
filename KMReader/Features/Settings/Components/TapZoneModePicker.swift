//
// TapZoneModePicker.swift
//
//

import SwiftUI

struct TapZoneModePicker: View {
  @Binding var selection: TapZoneMode
  let tapZoneInversionMode: TapZoneInversionMode
  let readingDirection: ReadingDirection

  private let columnCount = 3

  /// Tracks the reader surface's aspect so the preview flips between the
  /// portrait and landscape cover ratios on rotation; the picker's own shape
  /// says nothing about the reader surface.
  @State private var surfaceAspectRatio = PlatformHelper.readerSurfaceAspectRatio

  private var rows: [[TapZoneMode]] {
    let modes = TapZoneMode.allCases
    return stride(from: 0, to: modes.count, by: columnCount).map {
      Array(modes[$0..<min($0 + columnCount, modes.count)])
    }
  }

  private var previewAspectRatio: CGFloat {
    surfaceAspectRatio < 1 ? CoverAspectRatio.widthToHeight : CoverAspectRatio.heightToWidth
  }

  /// Eager rows rather than a LazyVGrid: inside a self-sizing List/Form row,
  /// the lazy grid can report two heights for the same width, which UIKit
  /// ends as a recursive layout loop crash.
  var body: some View {
    VStack(spacing: 12) {
      ForEach(rows, id: \.self) { row in
        HStack(alignment: .top, spacing: 12) {
          ForEach(row, id: \.self) { mode in
            modeButton(for: mode)
          }
          ForEach(row.count..<columnCount, id: \.self) { _ in
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
          }
        }
      }
    }
    .padding(.vertical, 4)
    .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in
      surfaceAspectRatio = PlatformHelper.readerSurfaceAspectRatio
    }
  }

  private func modeButton(for mode: TapZoneMode) -> some View {
    let isSelected = selection == mode

    return Button {
      selection = mode
    } label: {
      TapZonePreview(
        tapZoneMode: mode,
        tapZoneInversionMode: tapZoneInversionMode,
        readingDirection: readingDirection,
        previewAspectRatio: previewAspectRatio,
        caption: mode.displayName
      )
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .padding(8)
      .background(Color.secondary.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(isSelected ? Color.primary : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
