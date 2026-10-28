//
// NotableEntity.swift
//

import Foundation

nonisolated struct NotableEntity: Codable, Hashable, Sendable {
  let kind: String
  let name: String

  init(kind: String, name: String) {
    self.kind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var kindDisplayName: String {
    switch kind {
    case "character":
      return String(localized: "Characters")
    case "team":
      return String(localized: "Teams")
    case "location":
      return String(localized: "Locations")
    default:
      return kind.capitalized
    }
  }

  var filterKey: String {
    "\(kind)\u{1F}\(name)"
  }

  static func fromFilterKey(_ key: String) -> NotableEntity? {
    let components = key.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
    guard components.count == 2 else { return nil }
    return NotableEntity(kind: String(components[0]), name: String(components[1]))
  }

  static var knownKinds: [String] {
    ["character", "team", "location"]
  }

  static func kindDisplayName(_ kind: String) -> String {
    NotableEntity(kind: kind, name: "").kindDisplayName
  }
}

nonisolated extension Collection where Element == NotableEntity {
  func matches(_ entities: [NotableEntity]?, logic: FilterLogic) -> Bool {
    guard let entities, !entities.isEmpty else { return true }
    let candidates = Set((self).map(\.filterKey))
    switch logic {
    case .all:
      return entities.allSatisfy { candidates.contains($0.filterKey) }
    case .any:
      return entities.contains { candidates.contains($0.filterKey) }
    }
  }
}
