//
// ServerProfile.swift
//
//

import Foundation

/// What one server instance offers beyond Komga, read once per connection by
/// `ServerProfileService` instead of probing each kmrs-private endpoint.
nonisolated struct ServerProfile: Codable, Equatable, Sendable {
  /// Komga answers `/api/v1/server/info` with 404.
  var isKmrs: Bool
  var features: Set<ServerFeature>
  /// kmrs's "skip read books on next" setting, so offline next-book
  /// suggestions match what the server's `/next` would return.
  var skipReadOnNext: Bool
  /// kmrs's recent reading window in days, 0 = off: Keep Reading and On Deck
  /// only show series read within it.
  var recentReadingDays: Int

  static let komga = ServerProfile(
    isKmrs: false, features: [], skipReadOnNext: false, recentReadingDays: 0)

  init(isKmrs: Bool, features: Set<ServerFeature>, skipReadOnNext: Bool, recentReadingDays: Int) {
    self.isKmrs = isKmrs
    self.features = features
    self.skipReadOnNext = skipReadOnNext
    self.recentReadingDays = recentReadingDays
  }

  // Profiles stored before `recentReadingDays` existed decode with the window off.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isKmrs = try container.decode(Bool.self, forKey: .isKmrs)
    features = try container.decode(Set<ServerFeature>.self, forKey: .features)
    skipReadOnNext = try container.decode(Bool.self, forKey: .skipReadOnNext)
    recentReadingDays = try container.decodeIfPresent(Int.self, forKey: .recentReadingDays) ?? 0
  }

  func supports(_ feature: ServerFeature) -> Bool {
    features.contains(feature)
  }

  /// The earliest read date Keep Reading and On Deck keep, or nil when the
  /// window is off.
  func recentReadingCutoff(now: Date = Date()) -> Date? {
    guard recentReadingDays > 0 else { return nil }
    return now.addingTimeInterval(-Double(recentReadingDays) * 24 * 60 * 60)
  }
}
