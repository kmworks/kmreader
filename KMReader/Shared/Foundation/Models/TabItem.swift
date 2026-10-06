//
// TabItem.swift
//
//

import SwiftUI

enum TabItem: Hashable, Identifiable {
  case home
  case library
  case browse
  case offline
  case server
  case settings

  var id: String {
    switch self {
    case .home: return "home"
    case .library: return "library"
    case .browse: return "browse"
    case .offline: return "offline"
    case .server: return "server"
    case .settings: return "settings"
    }
  }

  var title: String {
    switch self {
    case .home:
      return String(localized: "title.dashboard")
    case .library:
      return String(localized: "tab.library", defaultValue: "Library")
    case .browse:
      #if os(iOS)
        return String(localized: "tab.search", defaultValue: "Search")
      #else
        return String(localized: "tab.browse")
      #endif
    case .offline:
      return String(localized: "tab.offline")
    case .server:
      return String(localized: "tab.server")
    case .settings:
      return String(localized: "tab.settings")
    }
  }

  var icon: String {
    switch self {
    case .home:
      return "house"
    case .library:
      return ContentIcon.library
    case .browse:
      return AppIcon.search
    case .offline:
      return "tray.and.arrow.down"
    case .server:
      return "server.rack"
    case .settings:
      return AppIcon.settings
    }
  }

  var label: some View {
    Label(title, systemImage: icon)
  }

  @ViewBuilder
  func content(context: AppViewContext) -> some View {
    switch self {
    case .home:
      DashboardView(
        authViewModel: context.authViewModel,
        readerPresentation: context.readerPresentation
      )
    case .library:
      LibraryBrowseView(authViewModel: context.authViewModel)
    case .browse:
      #if os(iOS)
        // iPhone Search tab: search-first, content browses in the Library tab.
        SearchBrowseView(authViewModel: context.authViewModel)
      #else
        BrowseView(authViewModel: context.authViewModel)
      #endif
    case .offline:
      OfflineView(authViewModel: context.authViewModel)
    case .server:
      ServerView(authViewModel: context.authViewModel)
    case .settings:
      SettingsView()
    }
  }
}
