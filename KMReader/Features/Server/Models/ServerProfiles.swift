//
// ServerProfiles.swift
//
//

import Foundation

/// Per-instance `ServerProfile`s, persisted through `AppConfig.serverProfiles`.
nonisolated struct ServerProfiles: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  var profilesByInstance: [String: ServerProfile]

  init(profilesByInstance: [String: ServerProfile] = [:]) {
    self.profilesByInstance = profilesByInstance
  }

  func profile(instanceId: String) -> ServerProfile? {
    profilesByInstance[instanceId]
  }

  mutating func set(_ profile: ServerProfile, instanceId: String) {
    profilesByInstance[instanceId] = profile
  }

  var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard
      let data = try? encoder.encode(profilesByInstance),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }

  init?(rawValue: String) {
    guard
      let data = rawValue.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([String: ServerProfile].self, from: data)
    else {
      self.profilesByInstance = [:]
      return
    }
    self.profilesByInstance = decoded
  }
}
