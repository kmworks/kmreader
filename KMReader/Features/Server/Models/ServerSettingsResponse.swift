//
// ServerSettingsResponse.swift
//
//

import Foundation

/// The part of `GET /api/v1/settings` the client reads: kmrs additions that
/// every user can read. Komga never sends them.
nonisolated struct ServerSettingsResponse: Decodable, Sendable {
  let skipReadOnNext: Bool?
  let recentReadingDays: Int?
}
