//
// ServerSkipReadOnNext.swift
//
//

import Foundation

/// Per-instance copy of the server's "skip read books on next" setting
/// (`skipReadOnNext`, kmrs only), so offline next-book suggestions match what
/// the server's `/next` would return. Servers that don't send it never skip.
nonisolated struct ServerSkipReadOnNext: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var valuesByInstance: [String: Bool]

  init(valuesByInstance: [String: Bool] = [:]) {
    self.valuesByInstance = valuesByInstance
  }

  func skipsRead(instanceId: String) -> Bool {
    valuesByInstance[instanceId] ?? false
  }

  mutating func set(_ skipsRead: Bool, instanceId: String) {
    valuesByInstance[instanceId] = skipsRead
  }

  var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard
      let data = try? encoder.encode(valuesByInstance),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }

  init?(rawValue: String) {
    guard
      let data = rawValue.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
    else {
      self.valuesByInstance = [:]
      return
    }
    self.valuesByInstance = decoded
  }
}
