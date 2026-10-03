//
// KomfIntegration.swift
//
//

import Foundation

/// kmrs-private komf integration status (GET /api/v1/komf/integration, admin only).
nonisolated struct KomfIntegration: Codable, Equatable, Sendable {
  static let connectedState = "connected"

  let configured: Bool
  let url: String?
  let baseUrl: String?
  let authKeySet: Bool
  let state: String?
  let lastError: String?
  let komfReachable: Bool

  var isConnected: Bool {
    state == Self.connectedState
  }
}
