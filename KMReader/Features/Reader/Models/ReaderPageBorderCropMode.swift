//
// ReaderPageBorderCropMode.swift
//
//

import Foundation

nonisolated enum ReaderPageBorderCropMode: String, CaseIterable, Hashable, Codable, Sendable {
  case disabled
  case conservative
  case aggressive

  var displayName: String {
    switch self {
    case .disabled:
      return String(localized: "Disabled")
    case .conservative:
      return String(localized: "Conservative", defaultValue: "Conservative")
    case .aggressive:
      return String(localized: "Aggressive", defaultValue: "Aggressive")
    }
  }
}
