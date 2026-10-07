//
// ActuatorSessionsResponse.swift
//
//

import Foundation

/// `GET /actuator/sessions` (admin only): every live session when no
/// `username` filter is passed.
nonisolated struct ActuatorSessionsResponse: Decodable, Sendable {
  let sessions: [Session]

  struct Session: Decodable, Sendable, Identifiable {
    let id: String
    /// ISO offset date-time strings, fractional seconds optional.
    let creationTime: String
    let lastAccessedTime: String
    let expired: Bool

    var createdAt: Date? {
      Self.parseDate(creationTime)
    }

    var lastAccessedAt: Date? {
      Self.parseDate(lastAccessedTime)
    }

    private static func parseDate(_ value: String) -> Date? {
      if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
        return date
      }
      return try? Date.ISO8601FormatStyle().parse(value)
    }
  }
}
