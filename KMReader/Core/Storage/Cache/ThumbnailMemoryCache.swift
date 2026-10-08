//
// ThumbnailMemoryCache.swift
//
//

import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// Decoded covers kept in memory: lazy grids and lists recreate their cells on
/// scroll, and without this cache every recreation re-reads and re-decodes the
/// disk cache, flashing the loading placeholder each time.
final class ThumbnailMemoryCache {
  static let shared = ThumbnailMemoryCache()

  private final class Entry {
    let image: PlatformImage
    let storedAt: Date

    init(image: PlatformImage) {
      self.image = image
      self.storedAt = Date()
    }
  }

  private let cache = NSCache<NSString, Entry>()

  private init() {
    // The byte budget binds first: a decoded cover runs ~240KB at ≤300px and
    // ~1.3MB at the iPad downsample cap, so the 512-count limit only comes
    // into play for small-cover servers.
    cache.countLimit = 512
    cache.totalCostLimit = 128 * 1024 * 1024
  }

  static nonisolated func key(id: String, type: ThumbnailType, page: Int? = nil, centerCropped: Bool)
    -> String
  {
    // The decode size depends on the display mode; keying on it makes a mode
    // switch miss and re-decode instead of serving the other mode's size.
    let mode = centerCropped ? "crop" : "fit"
    let base = "\(CacheNamespace.identifier())#\(type.rawValue)#\(id)#\(mode)"
    return page != nil ? "\(base)#\(page!)" : base
  }

  func image(forKey key: String) -> PlatformImage? {
    let nsKey = key as NSString
    guard let entry = cache.object(forKey: nsKey) else { return nil }
    // Honor the disk cache's expiration so a stale cover still re-validates.
    guard Date().timeIntervalSince(entry.storedAt) <= AppConfig.coverCacheExpirationInterval
    else {
      cache.removeObject(forKey: nsKey)
      return nil
    }
    return entry.image
  }

  func store(_ image: PlatformImage, forKey key: String) {
    let cost = Int(image.size.width * image.size.height * 4)
    cache.setObject(Entry(image: image), forKey: key as NSString, cost: cost)
  }

  func remove(forKey key: String) {
    cache.removeObject(forKey: key as NSString)
  }

  func removeAll() {
    cache.removeAllObjects()
  }
}
