//
// EpubTextAlignment.swift
//
//

import Foundation

nonisolated enum EpubTextAlignment: String, CaseIterable, Identifiable, Sendable {
  case publisherDefault = "publisherDefault"
  case start = "start"
  case justify = "justify"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .publisherDefault:
      return String(
        localized: "epub.text_alignment.publisher_default",
        defaultValue: "Publisher Default"
      )
    case .start:
      return String(localized: "epub.text_alignment.start", defaultValue: "Start")
    case .justify:
      return String(localized: "epub.text_alignment.justify", defaultValue: "Justify")
    }
  }

  var readiumTextAlign: String? {
    switch self {
    case .publisherDefault:
      return nil
    case .start:
      return "start"
    case .justify:
      return "justify"
    }
  }

  var readiumBodyHyphens: String? {
    switch self {
    case .publisherDefault:
      return nil
    case .start:
      return "none"
    case .justify:
      return "auto"
    }
  }
}
