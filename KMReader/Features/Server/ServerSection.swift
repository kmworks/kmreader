//
// ServerSection.swift
//
//

import SwiftUI

enum ServerSection: String, CaseIterable {

  case libraries
  case readingStats
  case serverInfo
  case tasks
  case history
  case media

  case servers
  case account
  case apiKeys
  case authenticationActivity

  var icon: String {
    switch self {
    case .libraries:
      return ContentIcon.library
    case .readingStats:
      return "chart.bar.doc.horizontal"
    case .serverInfo:
      return "server.rack"
    case .tasks:
      return "list.bullet.clipboard"
    case .history:
      return "clock.arrow.circlepath"
    case .media:
      return "doc.viewfinder"

    case .servers:
      return "externaldrive.connected.to.linebelow"
    case .account:
      return "person.crop.circle"
    case .apiKeys:
      return "key"
    case .authenticationActivity:
      return "person.badge.key"

    }
  }

  var color: Color {
    switch self {
    case .libraries:
      return .blue
    case .readingStats:
      return .indigo
    case .serverInfo:
      return .gray
    case .tasks:
      return .orange
    case .history:
      return .brown
    case .media:
      return .purple

    case .servers:
      return .gray
    case .account:
      return .green
    case .apiKeys:
      return .yellow
    case .authenticationActivity:
      return .gray
    }
  }

  var title: String {
    switch self {
    case .libraries:
      return String(localized: "Libraries")
    case .readingStats:
      return String(localized: "Reading Stats")
    case .serverInfo:
      return String(localized: "Server Info")
    case .tasks:
      return String(localized: "Tasks")
    case .history:
      return String(localized: "History")
    case .media:
      return String(localized: "Media")

    case .servers:
      return String(localized: "Servers")
    case .account:
      return String(localized: "Account")
    case .apiKeys:
      return String(localized: "API Keys")
    case .authenticationActivity:
      return String(localized: "Authentication Activity")
    }
  }
}
