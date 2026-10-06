//
// OfflineProtectionSource.swift
//
//

import Foundation

nonisolated struct OfflineProtectionSource: Equatable, Identifiable, Sendable {
  enum Kind: String, Sendable {
    case series
    case readList

    var systemImage: String {
      switch self {
      case .series:
        return ContentIcon.series
      case .readList:
        return ContentIcon.readList
      }
    }
  }

  let kind: Kind
  let sourceId: String
  let name: String

  var id: String {
    "\(kind.rawValue):\(sourceId)"
  }

  var displayName: String {
    name.isEmpty ? sourceId : name
  }
}
