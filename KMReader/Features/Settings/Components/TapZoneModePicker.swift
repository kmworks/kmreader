//
// TapZoneModePicker.swift
//
//

import SwiftUI

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

struct TapZoneModePicker: View {
  @Binding var selection: TapZoneMode
  let tapZoneInversionMode: TapZoneInversionMode
  let readingDirection: ReadingDirection

  private let columnCount = 3

  private var rows: [[TapZoneMode]] {
    let modes = TapZoneMode.allCases
    return stride(from: 0, to: modes.count, by: columnCount).map {
      Array(modes[$0..<min($0 + columnCount, modes.count)])
    }
  }

  private var previewAspectRatio: CGFloat {
    isPortraitScreen ? CoverAspectRatio.widthToHeight : CoverAspectRatio.heightToWidth
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

  private var isPortraitScreen: Bool {
    #if os(iOS) || os(tvOS)
      let size = UIScreen.main.bounds.size
    #elseif os(macOS)
      let size = NSScreen.main?.visibleFrame.size ?? CGSize(width: 16, height: 10)
    #else
      let size = CGSize(width: 16, height: 10)
    #endif

    return size.width < size.height
  }
}
