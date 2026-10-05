//
// SettingsSection.swift
//
//

import SwiftUI

enum SettingsSection: String, CaseIterable {
  case appearance
  case browse
  case dashboard
  case about
  case cache
  case divinaReader
  case reading
  #if os(iOS) || os(macOS)
    case pdfReader
  #endif
  #if os(iOS) || os(macOS)
    case epubTheme
    case epubSettings
  #endif
  case sse
  case systemFeatures
  case network
  case logs

  var icon: String {
    switch self {
    case .appearance:
      return "paintbrush"
    case .browse:
      return "square.grid.2x2"
    case .dashboard:
      return "house"
    case .about:
      return "info.circle.fill"
    case .cache:
      return "externaldrive"
    case .divinaReader:
      return "photo.on.rectangle.angled"
    case .reading:
      return "book"
    #if os(iOS) || os(macOS)
      case .pdfReader:
        return "doc.richtext"
    #endif
    #if os(iOS) || os(macOS)
      case .epubTheme:
        return "textformat.size"
      case .epubSettings:
        return "character.book.closed"
    #endif
    case .sse:
      return "antenna.radiowaves.left.and.right"
    case .systemFeatures:
      return "gearshape.2"
    case .network:
      return "network"
    case .logs:
      return "doc.text.magnifyingglass"
    }
  }

  var color: Color {
    switch self {
    case .appearance:
      return .blue
    case .browse:
      return .purple
    case .dashboard:
      return .orange
    case .about:
      return .gray
    case .cache:
      return .gray
    case .divinaReader:
      return .green
    case .reading:
      return .blue
    #if os(iOS) || os(macOS)
      case .pdfReader:
        return .red
    #endif
    #if os(iOS) || os(macOS)
      case .epubTheme:
        return .indigo
      case .epubSettings:
        return .mint
    #endif
    case .sse:
      return .orange
    case .systemFeatures:
      return .blue
    case .network:
      return .teal
    case .logs:
      return .brown
    }
  }

  var title: String {
    switch self {
    case .appearance:
      return String(localized: "Appearance")
    case .browse:
      return String(localized: "Browse")
    case .dashboard:
      return String(localized: "Dashboard")
    case .about:
      return String(localized: "About")
    case .cache:
      return String(localized: "Cache")
    case .divinaReader:
      return String(localized: "DIVINA Reader")
    case .reading:
      return String(localized: "Reader General")
    #if os(iOS) || os(macOS)
      case .pdfReader:
        return String(localized: "PDF Reader")
    #endif
    #if os(iOS) || os(macOS)
      case .epubTheme:
        return String(localized: "EPUB Theme")
      case .epubSettings:
        return String(localized: "EPUB Settings")
    #endif
    case .sse:
      return String(localized: "Real-time Updates")
    case .systemFeatures:
      return String(localized: "System Features")
    case .network:
      return String(localized: "Network")
    case .logs:
      return String(localized: "Logs")
    }
  }
}
