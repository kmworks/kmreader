//
// SettingsManagementView.swift
//
//

import SwiftUI

/// iPhone-only sub-page holding the server management entries that live
/// inline in Settings on larger platforms' Server tab.
struct SettingsManagementView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()

  var body: some View {
    Form {
      Section {
        NavigationLink(value: NavDestination.settingsLibraries) {
          SettingsBadgeRow(
            title: ServerSection.libraries.title,
            icon: ServerSection.libraries.icon,
            color: ServerSection.libraries.color
          )
        }
      }

      if current.isAdmin {
        Section {
          NavigationLink(value: NavDestination.settingsServerInfo) {
            SettingsBadgeRow(
              title: ServerSection.serverInfo.title,
              icon: ServerSection.serverInfo.icon,
              color: ServerSection.serverInfo.color
            )
          }
          NavigationLink(value: NavDestination.settingsTasks) {
            SettingsBadgeRow(
              title: ServerSection.tasks.title,
              icon: ServerSection.tasks.icon,
              color: ServerSection.tasks.color,
              badge: taskQueueStatus.count > 0 ? "\(taskQueueStatus.count)" : nil,
              badgeColor: .secondary
            )
          }
          NavigationLink(value: NavDestination.settingsHistory) {
            SettingsBadgeRow(
              title: ServerSection.history.title,
              icon: ServerSection.history.icon,
              color: ServerSection.history.color
            )
          }
          NavigationLink(value: NavDestination.settingsMedia) {
            SettingsBadgeRow(
              title: ServerSection.media.title,
              icon: ServerSection.media.icon,
              color: ServerSection.media.color
            )
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Management"))
  }
}
