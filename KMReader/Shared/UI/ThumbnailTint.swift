//
// ThumbnailTint.swift
//
//

import SwiftUI

/// View-side loader for a thumbnail's card tint: loads once per thumbnail.
/// Views forward `.thumbnailDidRefresh` notifications to `reloadIfMatches(_:)`
/// so cards pick up cover changes the same way `ThumbnailImage` does.
@Observable
@MainActor
final class ThumbnailTint {
  private(set) var color: Color?

  private var loadedKey: String?
  private var loadTask: Task<Void, Never>?

  /// Seeds a cached tint synchronously so the first render is already tinted.
  /// Marks the thumbnail as loaded, so `load` only fetches on a cache miss.
  func warm(id: String, type: ThumbnailType) {
    guard let cached = ThumbnailTintColorCache.shared.cachedColor(id: id, type: type) else { return }
    color = cached
    loadedKey = "\(type.rawValue)#\(id)"
  }

  func load(id: String, type: ThumbnailType) {
    let key = "\(type.rawValue)#\(id)"
    guard loadedKey != key else { return }
    loadedKey = key
    color = nil
    fetch(id: id, type: type, key: key, invalidate: false)
  }

  func reloadIfMatches(_ notification: Notification) {
    guard
      let key = loadedKey,
      let id = notification.userInfo?["id"] as? String,
      let typeRaw = notification.userInfo?["type"] as? String,
      let type = ThumbnailType(rawValue: typeRaw),
      key == "\(typeRaw)#\(id)"
    else { return }
    fetch(id: id, type: type, key: key, invalidate: true)
  }

  private func fetch(id: String, type: ThumbnailType, key: String, invalidate: Bool) {
    loadTask?.cancel()
    loadTask = Task {
      if invalidate {
        ThumbnailTintColorCache.shared.invalidate(id: id, type: type)
      }
      let tint = await ThumbnailTintColorCache.shared.color(id: id, type: type)
      guard !Task.isCancelled, loadedKey == key else { return }
      color = tint
    }
  }
}
