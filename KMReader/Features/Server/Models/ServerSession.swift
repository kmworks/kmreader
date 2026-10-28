//
// ServerSession.swift
//

import Foundation

nonisolated struct ServerSession: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let creationTime: String
  let lastAccessedTime: String
  let isCurrent: Bool
  let expired: Bool
  let email: String?
  let userId: String?

  init(
    id: String,
    creationTime: String,
    lastAccessedTime: String,
    isCurrent: Bool = false,
    expired: Bool = false,
    email: String? = nil,
    userId: String? = nil
  ) {
    self.id = id
    self.creationTime = creationTime
    self.lastAccessedTime = lastAccessedTime
    self.isCurrent = isCurrent
    self.expired = expired
    self.email = email
    self.userId = userId
  }

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

nonisolated extension ActuatorSessionsResponse.Session {
  var serverSession: ServerSession {
    ServerSession(
      id: id,
      creationTime: creationTime,
      lastAccessedTime: lastAccessedTime,
      isCurrent: false,
      expired: expired,
      email: nil,
      userId: nil
    )
  }
}
