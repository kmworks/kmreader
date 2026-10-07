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
  let createdDate: Date
  let lastModifiedDate: Date

  enum Target: String, Codable, Sendable {
    case book = "BOOK"
    case series = "SERIES"
  }

  enum Visibility: String, Codable, Sendable {
    case `private` = "PRIVATE"
    case `public` = "PUBLIC"
    case shared = "SHARED"
  }

  var targetDisplayName: String {
    switch target {
    case .book: return String(localized: "browse.content.books")
    case .series: return String(localized: "browse.content.series")
    }
  }

  /// Private is the common case and gets no badge.
  var visibilityDisplayName: String? {
    switch visibility {
    case .private: return nil
    case .public: return String(localized: "smartlist.visibility.public")
    case .shared: return String(localized: "smartlist.visibility.shared")
    }
  }
}
