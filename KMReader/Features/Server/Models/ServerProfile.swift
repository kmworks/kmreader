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

  static let komga = ServerProfile(isKmrs: false, features: [], skipReadOnNext: false)

  func supports(_ feature: ServerFeature) -> Bool {
    features.contains(feature)
  }
}
