//
// ServerDisplayItem.swift
//

import Foundation

nonisolated struct ServerDisplayItem: Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let serverURL: String
  let endpoints: [ServerEndpoint]
  let username: String
  let authToken: String
  let isAdmin: Bool
  let authMethod: AuthenticationMethod
  let protected: Bool
  let lastUsedAt: Date

  var instanceId: String {
    id.uuidString
  }

  var displayName: String {
    name.isEmpty ? serverURL : name
  }

  var hasMultipleEndpoints: Bool {
    endpoints.count > 1
  }

  var activeEndpoint: ServerEndpoint {
    let normalizedActive = Current.normalizeServerURL(serverURL)
    return endpoints.first(where: { $0.normalizedURL == normalizedActive })
      ?? ServerEndpoint(url: normalizedActive)
  }
}
