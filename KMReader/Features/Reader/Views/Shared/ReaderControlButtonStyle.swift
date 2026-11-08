//
// ReaderControlButtonStyle.swift
//
//

import SwiftUI

extension View {
  @ViewBuilder
  func readerHeaderTitleControlFrame() -> some View {
    #if os(tvOS)
      self.frame(minHeight: 64, alignment: .center)
    #else
      self.frame(minHeight: 24, alignment: .center)
    #endif
  }

  @ViewBuilder
  func readerControlButtonStyle(isActive: Bool = false) -> some View {
    #if os(iOS)
      if #available(iOS 26.0, *) {
        self.adaptiveButtonStyle(isActive ? .borderedProminent : .bordered)
      } else {
        self
          .buttonStyle(.borderedProminent)
          .tint(isActive ? .prominentButtonTint : .readerTint)
          .foregroundStyle(isActive ? .prominentButtonForeground : .white)
      }
    #else
      self.adaptiveButtonStyle(isActive ? .borderedProminent : .bordered)
    #endif
  }
}
