//
// EpubOverlayTextItem.swift
//
//

import Foundation

nonisolated enum EpubOverlayTextItem: String, CaseIterable, Identifiable, Sendable {
  case none
  case bookTitle
  case chapterTitle
  case bookProgressPercent
  case bookRemainingPercent
  case chapterProgressPercent
  case chapterRemaining
  case chapterPosition

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .none:
      return String(localized: "epub.overlay.item.none", defaultValue: "None")
    case .bookTitle:
      return String(localized: "epub.overlay.item.book_title", defaultValue: "Book Title")
    case .chapterTitle:
      return String(localized: "epub.overlay.item.chapter_title", defaultValue: "Chapter Title")
    case .bookProgressPercent:
      return String(localized: "epub.overlay.item.book_progress", defaultValue: "Book Progress")
    case .bookRemainingPercent:
      return String(localized: "epub.overlay.item.book_remaining", defaultValue: "Book Remaining")
    case .chapterProgressPercent:
      return String(localized: "epub.overlay.item.chapter_progress", defaultValue: "Chapter Progress")
    case .chapterRemaining:
      return String(localized: "epub.overlay.item.chapter_remaining", defaultValue: "Chapter Remaining")
    case .chapterPosition:
      return String(localized: "epub.overlay.item.chapter_page", defaultValue: "Chapter Page")
    }
  }
}
