//
// BrowseContentType.swift
//
//

import Foundation

enum BrowseContentType: String, CaseIterable, Identifiable {
  case series
  case books
  case collections
  case readlists

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .series: return String(localized: "browse.content.series")
    case .books: return String(localized: "browse.content.books")
    case .collections: return String(localized: "browse.content.collections")
    case .readlists: return String(localized: "browse.content.readlists")
    }
  }

  var icon: String {
    switch self {
    case .series: return ContentIcon.series
    case .books: return ContentIcon.book
    case .collections: return ContentIcon.collection
    case .readlists: return ContentIcon.readList
    }
  }

  var supportsReadStatusFilter: Bool {
    switch self {
    case .series, .books:
      return true
    case .collections, .readlists:
      return false
    }
  }

  var supportsSeriesStatusFilter: Bool {
    self == .series
  }

  var supportsSorting: Bool {
    switch self {
    case .series, .books:
      return true
    case .collections, .readlists:
      return false
    }
  }

  /// Browse surfaces offer only series/books — collections and read lists
  /// live on the Lists page — so a persisted collections/read lists pick
  /// resolves to series.
  static func effective(
    fixed: BrowseContentType?,
    persisted: BrowseContentType
  ) -> BrowseContentType {
    if let fixed {
      return fixed
    }
    if persisted != .series, persisted != .books {
      return .series
    }
    return persisted
  }
}
