//
// SmartList.swift
//
//

import Foundation

/// A kmrs-server saved search evaluated live server-side. Stock Komga has no
/// smart lists; the whole API 404s there.
nonisolated struct SmartList: Codable, Identifiable, Sendable, Equatable, Hashable {
  let id: String
  let name: String
  let summary: String
  let ownerId: String
  let target: Target
  let visibility: Visibility
  let sharedWithUserIds: [String]
  let search: [String: JSONAny]?
  let createdDate: Date
  let lastModifiedDate: Date

  enum Target: String, Codable, Sendable {
    case book = "BOOK"
    case series = "SERIES"
  }

  enum Visibility: String, Codable, CaseIterable, Sendable {
    case `private` = "PRIVATE"
    case `public` = "PUBLIC"
    case shared = "SHARED"

    var displayName: String {
      switch self {
      case .private: return String(localized: "smartlist.visibility.private")
      case .public: return String(localized: "smartlist.visibility.public")
      case .shared: return String(localized: "smartlist.visibility.shared")
      }
    }
  }

  // JSONAny is not Hashable; the search document is excluded from hashing.
  // Equal lists still hash equally, only collisions get more likely.
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  var targetDisplayName: String {
    switch target {
    case .book: return String(localized: "browse.content.books")
    case .series: return String(localized: "browse.content.series")
    }
  }

  /// Private is the common case and gets no badge.
  var visibilityDisplayName: String? {
    visibility == .private ? nil : visibility.displayName
  }
}
