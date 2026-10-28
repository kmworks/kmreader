//
// NativeServerSession.swift
//

import Foundation

nonisolated struct NativeServerSession: Codable, Sendable {
  let id: String
  let creationTime: String
  let lastAccessedTime: String
  let current: Bool?
  let userId: String?
  let email: String?

  var serverSession: ServerSession {
    ServerSession(
      id: id,
      creationTime: creationTime,
      lastAccessedTime: lastAccessedTime,
      isCurrent: current ?? false,
      email: email,
      userId: userId
    )
  }
}
