//
// MetadataFilterDisplayStyle.swift
//
//

import Foundation

enum MetadataFilterDisplayStyle: Sendable {
  case plain
  case language
  case ageRating
  case notableEntity

  func displayName(for value: String) -> String {
    switch self {
    case .plain:
      return value
    case .language:
      return LanguageCodeHelper.displayName(for: value)
    case .ageRating:
      return "\(value)+"
    case .notableEntity:
      guard let entity = NotableEntity.fromFilterKey(value) else { return value }
      return "\(entity.kindDisplayName) · \(entity.name)"
    }
  }
}
