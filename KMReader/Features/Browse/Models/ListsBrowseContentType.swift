//
// ListsBrowseContentType.swift
//
//

import Foundation

/// The Lists page's content types — the `BrowseContentType` subset without
/// series/books, so Lists pages switch exhaustively over what they support.
enum ListsBrowseContentType: String, CaseIterable, Identifiable {
  case collections
  case readlists
  case smartlists

  var id: String { rawValue }

  var browseContentType: BrowseContentType {
    switch self {
    case .collections: return .collections
    case .readlists: return .readlists
    case .smartlists: return .smartlists
    }
  }

  var displayName: String {
    browseContentType.displayName
  }

  /// Smart lists have no library filter.
  var supportsLibraryScope: Bool {
    self != .smartlists
  }
}
