//
// ServerEndpoint.swift
//

import Foundation

nonisolated struct ServerEndpoint: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var url: String

  init(id: UUID = UUID(), name: String = "", url: String) {
    self.id = id
    self.name = name
    self.url = Current.normalizeServerURL(url)
  }

  var normalizedURL: String {
    Current.normalizeServerURL(url)
  }

  var hasCustomName: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? displayURL : trimmed
  }

  /// Scheme-less URL for display (`https://host:25600/komga` → `host:25600/komga`).
  var displayURL: String {
    Self.displayURL(for: normalizedURL)
  }

  static func displayURL(for url: String) -> String {
    let normalized = Current.normalizeServerURL(url)
    if let schemeSeparator = normalized.range(of: "://") {
      return String(normalized[schemeSeparator.upperBound...])
    }
    return normalized
  }

  static func decodeEndpoints(_ rawValue: String?) -> [ServerEndpoint] {
    guard let rawValue, let data = rawValue.data(using: .utf8),
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return []
    }
    return normalized(
      array.compactMap { dict in
        guard let url = dict["url"] as? String else { return nil }
        let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let name = dict["name"] as? String ?? ""
        return ServerEndpoint(id: id, name: name, url: url)
      })
  }

  static func encodeEndpoints(_ endpoints: [ServerEndpoint]) -> String {
    let payload: [[String: Any]] = normalized(endpoints).map { endpoint in
      [
        "id": endpoint.id.uuidString,
        "name": endpoint.name,
        "url": endpoint.normalizedURL,
      ]
    }
    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let encoded = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return encoded
  }

  static func normalized(_ endpoints: [ServerEndpoint]) -> [ServerEndpoint] {
    var seen = Set<String>()
    var result: [ServerEndpoint] = []
    for endpoint in endpoints {
      let url = endpoint.normalizedURL
      guard !url.isEmpty, seen.insert(url).inserted else { continue }
      result.append(
        ServerEndpoint(
          id: endpoint.id,
          name: endpoint.name.trimmingCharacters(in: .whitespacesAndNewlines),
          url: url
        )
      )
    }
    return result
  }
}
