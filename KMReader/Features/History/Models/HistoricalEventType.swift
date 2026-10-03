//
// HistoricalEventType.swift
//
//

import SwiftUI

enum HistoricalEventType: String, CaseIterable {
  case bookFileDeleted = "BookFileDeleted"
  case seriesFolderDeleted = "SeriesFolderDeleted"
  case bookConverted = "BookConverted"
  case bookImported = "BookImported"
  case duplicatePageDeleted = "DuplicatePageDeleted"
  case bookTrashed = "BookTrashed"
  case seriesTrashed = "SeriesTrashed"
  case bookPurged = "BookPurged"
  case seriesPurged = "SeriesPurged"

  var label: String {
    switch self {
    case .bookFileDeleted:
      return String(localized: "history.event.bookFileDeleted", defaultValue: "Book File Deleted")
    case .seriesFolderDeleted:
      return String(localized: "history.event.seriesFolderDeleted", defaultValue: "Series Folder Deleted")
    case .bookConverted:
      return String(localized: "history.event.bookConverted", defaultValue: "Book Converted")
    case .bookImported:
      return String(localized: "history.event.bookImported", defaultValue: "Book Imported")
    case .duplicatePageDeleted:
      return String(localized: "history.event.duplicatePageDeleted", defaultValue: "Duplicate Page Deleted")
    case .bookTrashed:
      return String(localized: "history.event.bookTrashed", defaultValue: "Book Trashed")
    case .seriesTrashed:
      return String(localized: "history.event.seriesTrashed", defaultValue: "Series Trashed")
    case .bookPurged:
      return String(localized: "history.event.bookPurged", defaultValue: "Book Purged")
    case .seriesPurged:
      return String(localized: "history.event.seriesPurged", defaultValue: "Series Purged")
    }
  }

  var color: Color {
    switch self {
    case .bookFileDeleted:
      return .red
    case .seriesFolderDeleted:
      return .orange
    case .bookConverted:
      return .blue
    case .bookImported:
      return .green
    case .duplicatePageDeleted:
      return .purple
    case .bookTrashed:
      return .orange
    case .seriesTrashed:
      return .yellow
    case .bookPurged:
      return .pink
    case .seriesPurged:
      return .indigo
    }
  }
}
