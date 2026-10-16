//
// EpubThemePresetDisplayItem.swift
//
//

import Foundation

nonisolated struct EpubThemePresetDisplayItem: Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let preferencesJSON: String
  let updatedAt: Date

  var preferences: EpubThemePreferences? {
    EpubThemePreferences(rawValue: preferencesJSON)
  }
}
