//
// ServerSettingsResponse.swift
//
//

import Foundation

/// The part of `GET /api/v1/settings` the client reads. `skipReadOnNext` is a
/// kmrs addition that every user can read; Komga never sends it.
nonisolated struct ServerSettingsResponse: Decodable, Sendable {
  let skipReadOnNext: Bool?
}
