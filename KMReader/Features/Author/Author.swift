//
// Author.swift
//
//

import Foundation

nonisolated struct Author: Equatable, Hashable, Sendable {
  let name: String
  let role: AuthorRole

  init(name: String, role: AuthorRole) {
    self.name = name
    self.role = role
  }

  init(name: String, role: String) {
    self.name = name
    self.role = AuthorRole(from: role)
  }
}

// MARK: - Codable
nonisolated extension Author: Codable {
  enum CodingKeys: String, CodingKey {
    case name
    case role
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    role = AuthorRole(from: try container.decode(String.self, forKey: .role))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(role.rawValue, forKey: .role)
  }
}

// MARK: - Array Extension
nonisolated extension Array where Element == Author {
  /// Sorts authors by role order, then by name within the same role using
  /// locale-aware ICU collation (respects the app language and keeps the
  /// same-role ordering deterministic).
  func sortedByRole() -> [Author] {
    sorted { lhs, rhs in
      if lhs.role.sortOrder != rhs.role.sortOrder {
        return lhs.role.sortOrder < rhs.role.sortOrder
      }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }

  /// The one author worth surfacing where only a single name fits (card text lines).
  var primary: Author? {
    sortedByRole().first
  }
}
