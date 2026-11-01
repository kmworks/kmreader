//
// PanelDetectionProvider.swift
//
//

import CoreGraphics

protocol PanelDetectionProvider: Sendable {
  var version: String { get }
  /// Detect a page's panels (plus text/body for content-aware composition) as normalized boxes.
  /// Detection is direction-agnostic; reading order is applied later by `PanelComposition`.
  func detect(image: CGImage) async -> PageDetection
}
