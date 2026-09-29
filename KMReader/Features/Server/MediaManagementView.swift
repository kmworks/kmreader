//
// MediaManagementView.swift
//
//

import SwiftUI

struct MediaManagementView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else {
        Section {
          NavigationLink(value: NavDestination.settingsMediaAnalysis) {
            Label(String(localized: "Media Analysis"), systemImage: "exclamationmark.triangle")
          }
          NavigationLink(value: NavDestination.settingsMediaMissingPosters) {
            Label(String(localized: "Missing Posters"), systemImage: "photo")
          }
        }

        Section {
          NavigationLink(value: NavDestination.settingsMediaDuplicateFiles) {
            Label(String(localized: "Duplicate Files"), systemImage: "doc.on.doc")
          }
        }

        Section(String(localized: "Duplicate Pages")) {
          NavigationLink(value: NavDestination.settingsMediaDuplicatePagesKnown) {
            Label(String(localized: "Known"), systemImage: "checkmark.circle")
          }
          NavigationLink(value: NavDestination.settingsMediaDuplicatePagesUnknown) {
            Label(String(localized: "New"), systemImage: "questionmark.circle")
          }
        }
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(ServerSection.media.title)
  }
}
