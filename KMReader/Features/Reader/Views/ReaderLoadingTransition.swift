//
// ReaderLoadingTransition.swift
//
//

import SwiftUI

enum ReaderLoadingTransition {
  static let animation: Animation = .appCurve()
  static let content: AnyTransition = .opacity
  static let loading: AnyTransition = .opacity.combined(with: .scale(scale: 0.98))
}

extension View {
  func readerLoadingContent(isVisible: Bool) -> some View {
    opacity(isVisible ? 1 : 0)
      .allowsHitTesting(isVisible)
      .transition(ReaderLoadingTransition.content)
  }

  func readerLoadingOverlay() -> some View {
    zIndex(1)
      .transition(ReaderLoadingTransition.loading)
  }
}
