//
// EpubThemePreset.swift
//

import Foundation

nonisolated struct EpubThemePreset: Codable, Equatable, Sendable {
  var id: UUID
  var name: String
  var preferencesJSON: String
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    preferencesJSON: String,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.preferencesJSON = preferencesJSON
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

nonisolated extension EpubThemePreset {
  @MainActor
  func getPreferences() -> EpubThemePreferences? {
    return EpubThemePreferences(rawValue: preferencesJSON)
  }

  @MainActor
  static func create(
    name: String,
    preferences: EpubThemePreferences
  ) -> EpubThemePreset {
    return EpubThemePreset(
      name: name,
      preferencesJSON: preferences.rawValue
    )
  }
}
