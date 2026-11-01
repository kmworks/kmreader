//
// PanelModelLocation.swift
//
//

import Foundation

/// Where the panel detection model lives on disk, plus a version that tags its cached results so
/// a model update re-detects pages instead of serving the previous model's panels.
nonisolated struct PanelModelLocation: Hashable, Sendable {
  /// A compiled `.mlmodelc` at a stable path. A `.mlpackage` also loads, but is recompiled on
  /// every launch and cannot be prepared ahead of time.
  let url: URL
  let version: String

  /// The installed panel model, read when a reader opens. The model is delivered through the
  /// model catalog rather than bundled with the app; until one is installed this is nil and
  /// panel mode shows every page whole.
  static var installed: PanelModelLocation? {
    nil
  }
}
