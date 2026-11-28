//
// KomgaInstance.swift
//

import Foundation

nonisolated struct KomgaInstance: Codable, Equatable, Sendable {
  var id: UUID
  var name: String
  var serverURL: String
  var username: String
  var authToken: String
  var isAdmin: Bool
  var authMethod: AuthenticationMethod?
  var apiKeyId: String?
  var protected: Bool
  var selectedLibraryIdsRaw: String?
  var endpointsRaw: String?
  var createdAt: Date
  var lastUsedAt: Date
  var seriesLastSyncedAt: Date
  var booksLastSyncedAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    serverURL: String,
    username: String,
    authToken: String,
    isAdmin: Bool,
    authMethod: AuthenticationMethod = .basicAuth,
    apiKeyId: String? = nil,
    protected: Bool = false,
    selectedLibraryIdsRaw: String? = nil,
    endpointsRaw: String? = nil,
    createdAt: Date = Date(),
    lastUsedAt: Date = Date(),
    seriesLastSyncedAt: Date = Date(timeIntervalSince1970: 0),
    booksLastSyncedAt: Date = Date(timeIntervalSince1970: 0)
  ) {
    self.id = id
    self.name = name
    self.serverURL = serverURL
    self.username = username
    self.authToken = authToken
    self.isAdmin = isAdmin
    self.authMethod = authMethod
    self.apiKeyId = apiKeyId
    self.protected = protected
    self.selectedLibraryIdsRaw = selectedLibraryIdsRaw
    self.endpointsRaw = endpointsRaw
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
    self.seriesLastSyncedAt = seriesLastSyncedAt
    self.booksLastSyncedAt = booksLastSyncedAt
  }
}

nonisolated extension KomgaInstance {
  var displayName: String {
    name.isEmpty ? serverURL : name
  }

  var resolvedAuthMethod: AuthenticationMethod {
    authMethod ?? .basicAuth
  }

  var selectedLibraryIds: [String] {
    get {
      Self.decodeSelectedLibraryIds(selectedLibraryIdsRaw)
    }
    set {
      selectedLibraryIdsRaw = Self.encodeSelectedLibraryIds(newValue)
    }
  }

  static func decodeSelectedLibraryIds(_ rawValue: String?) -> [String] {
    guard let rawValue, let data = rawValue.data(using: .utf8) else { return [] }
    guard let values = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
    var seen = Set<String>()
    return values.filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  var endpoints: [ServerEndpoint] {
    get {
      let decoded = ServerEndpoint.decodeEndpoints(endpointsRaw)
      let base = decoded.isEmpty ? [ServerEndpoint(url: serverURL)] : decoded
      let normalizedActive = Current.normalizeServerURL(serverURL)
      guard !normalizedActive.isEmpty,
        !base.contains(where: { $0.normalizedURL == normalizedActive })
      else {
        return base
      }
      return [ServerEndpoint(url: normalizedActive)] + base
    }
    set {
      let normalized = ServerEndpoint.normalized(newValue)
      endpointsRaw = ServerEndpoint.encodeEndpoints(normalized)
      if !normalized.contains(where: { $0.normalizedURL == Current.normalizeServerURL(serverURL) }),
        let first = normalized.first
      {
        serverURL = first.normalizedURL
      }
    }
  }

  var activeEndpoint: ServerEndpoint {
    let normalizedActive = Current.normalizeServerURL(serverURL)
    return endpoints.first(where: { $0.normalizedURL == normalizedActive })
      ?? ServerEndpoint(url: normalizedActive)
  }

  func containsServerURL(_ url: String) -> Bool {
    let normalized = Current.normalizeServerURL(url)
    guard !normalized.isEmpty else { return false }
    return endpoints.contains { $0.normalizedURL == normalized }
  }

  static func encodeSelectedLibraryIds(_ libraryIds: [String]) -> String {
    var seen = Set<String>()
    let normalized = libraryIds.filter { !$0.isEmpty && seen.insert($0).inserted }
    guard
      let data = try? JSONSerialization.data(withJSONObject: normalized, options: []),
      let encoded = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return encoded
  }
}
