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

  /// The installed panel model, read when a reader opens.
  static var installed: PanelModelLocation? {
    guard let storage = try? ModelStorage.shared else { return nil }
    PanelModelLibrary.reconcile(storage: storage)
    guard let archive = PanelModelLibrary.installedArchive() else { return nil }
    return PanelModelLocation(
      url: storage.storage(for: archive).compiledDirectory.appendingPathComponent("detector-model.mlmodelc"),
      version: PanelModelLibrary.activeVersion ?? "\(archive.version)-\(archive.sha256.prefix(12))"
    )
  }
}
