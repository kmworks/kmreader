//
// PanelCacheKey.swift
//
//

import Foundation

/// Collision-safe identity for a cached `PanelSequence`, rendered to a stable string
/// `fingerprint` used as the cache key. A changed image, detector, direction, or
/// instance yields a different fingerprint (a miss), so stale rects can't survive an
/// image update or a detector change.
struct PanelCacheKey {
  /// Per-page image identity. Dimensions when the API exposes them, otherwise a
  /// descriptor fallback. The two are distinct shapes, so a page missing dimensions
  /// can never collide with a dimensioned one.
  enum ImageIdentity {
    case dimensions(width: Int, height: Int, sizeBytes: Int64)
    case descriptor(fileName: String, mediaType: String)
  }

  /// Bumped when preprocessing / splitting / ordering changes in a way that invalidates
  /// cached sequences.
  static let preprocessingVersion = "split-4"

  let instanceId: String
  let bookId: String
  let pageNumber: Int
  let imageIdentity: ImageIdentity
  let detectorVersion: String
  let direction: ReadingDirection
  let preprocessingVersion: String

  init(
    instanceId: String,
    bookId: String,
    page: BookPage,
    detectorVersion: String,
    direction: ReadingDirection
  ) {
    self.instanceId = instanceId
    self.bookId = bookId
    self.pageNumber = page.number
    self.imageIdentity = Self.makeImageIdentity(for: page)
    self.detectorVersion = detectorVersion
    self.direction = direction
    self.preprocessingVersion = Self.preprocessingVersion
  }

  /// Stable, delimiter-safe cache key. User-controlled fields are escaped so distinct
  /// inputs cannot forge a separator and collide onto one key.
  var fingerprint: String {
    let imageComponent: String
    switch imageIdentity {
    case .dimensions(let width, let height, let sizeBytes):
      imageComponent = "dim:\(width)x\(height)x\(sizeBytes)"
    case .descriptor(let fileName, let mediaType):
      imageComponent = "desc:\(Self.escape(fileName)):\(Self.escape(mediaType))"
    }
    return [
      "v1",
      Self.escape(instanceId),
      Self.escape(bookId),
      String(pageNumber),
      imageComponent,
      Self.escape(detectorVersion),
      String(describing: direction),
      Self.escape(preprocessingVersion),
    ].joined(separator: "|")
  }

  private static func makeImageIdentity(for page: BookPage) -> ImageIdentity {
    if let width = page.width, let height = page.height, let sizeBytes = page.sizeBytes {
      return .dimensions(width: width, height: height, sizeBytes: sizeBytes)
    }
    return .descriptor(fileName: page.fileName, mediaType: page.mediaType)
  }

  /// Escape the delimiters (`%`, `|`, `:`) so user strings can't forge separators.
  private static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "%", with: "%25")
      .replacingOccurrences(of: "|", with: "%7C")
      .replacingOccurrences(of: ":", with: "%3A")
  }
}
