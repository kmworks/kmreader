//
// SettingsView.swift
//
//

import SwiftUI

struct SettingsView: View {
  let authViewModel: AuthViewModel

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var isCheckingConnection = false

  /// iPhone has no Server tab; the current-server card and server
  /// management/account entries live in Settings instead.
  /// iPad keeps the sidebar Server page, tvOS keeps its Server tab.
  private var showsServerSections: Bool {
    #if os(iOS)
      return !PlatformHelper.isPad
    #else
      return false
    #endif
  }

  var body: some View {
    Form {
      if showsServerSections {
        Section {
          SettingsServerCardView()
        }

        Section {
          if current.isAdmin {
            NavigationLink(value: NavDestination.settingsLibraries) {
              SettingsBadgeRow(
                title: ServerSection.libraries.title,
                icon: ServerSection.libraries.icon,
                color: ServerSection.libraries.color
              )
            }
          }
          NavigationLink(value: NavDestination.settingsAccount) {
            SettingsBadgeRow(
              title: ServerSection.account.title,
              icon: ServerSection.account.icon,
              color: ServerSection.account.color
            )
          }
        }
      }

      Section {
        NavigationLink(value: NavDestination.settingsAppearance) {
          SettingsSectionRow(section: .appearance)
        }
        NavigationLink(value: NavDestination.settingsBrowse) {
          SettingsSectionRow(section: .browse)
        }
        NavigationLink(value: NavDestination.settingsDashboard) {
          SettingsSectionRow(section: .dashboard)
        }
      }

      Section {
        NavigationLink(value: NavDestination.settingsReadingStats) {
          SettingsSectionRow(section: .readingStats)
        }
      }

      Section {
        NavigationLink(value: NavDestination.settingsReading) {
          SettingsSectionRow(section: .reading)
        }
        NavigationLink(value: NavDestination.settingsDivinaReader) {
          SettingsSectionRow(section: .divinaReader)
        }
        #if os(iOS) || os(macOS)
          NavigationLink(value: NavDestination.settingsPdfReader) {
            SettingsSectionRow(section: .pdfReader)
          }
        #endif
        #if os(iOS)
          NavigationLink(value: NavDestination.settingsEpubTheme) {
            SettingsSectionRow(section: .epubTheme)
          }
          NavigationLink(value: NavDestination.settingsEpubSettings) {
            SettingsSectionRow(section: .epubSettings)
          }
        #endif
      }

      if showsServerSections, current.isAdmin {
        Section {
          NavigationLink(value: NavDestination.settingsServerInfo) {
            SettingsBadgeRow(
              title: ServerSection.serverInfo.title,
              icon: ServerSection.serverInfo.icon,
              color: ServerSection.serverInfo.color,
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

      Section {
        NavigationLink(value: NavDestination.settingsSSE) {
          SettingsSectionRow(section: .sse)
        }
        #if os(iOS)
          NavigationLink(value: NavDestination.settingsSystemFeatures) {
            SettingsSectionRow(section: .systemFeatures)
          }
        #endif
      }

      Section {
        #if os(iOS) || os(macOS)
          NavigationLink(value: NavDestination.settingsNetwork) {
            SettingsSectionRow(section: .network)
          }
        #endif
        NavigationLink(value: NavDestination.settingsCache) {
          SettingsSectionRow(section: .cache)
        }

        NavigationLink(value: NavDestination.settingsLogs) {
          SettingsSectionRow(section: .logs)
        }
      }

      Section {
        NavigationLink(value: NavDestination.settingsAbout) {
          SettingsSectionRow(section: .about)
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "title.settings"))
    #if os(iOS)
      .toolbar {
        if !PlatformHelper.isPad {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              if isOffline {
                Task {
                  await reconnect()
                }
              } else {
                OfflineManager.enterManualOfflineMode()
              }
            } label: {
              if isCheckingConnection {
                LoadingIcon()
              } else {
                Image(systemName: isOffline ? "wifi" : "wifi.slash")
              }
            }
            .disabled(isCheckingConnection)
          }
        }
      }
    #endif
  }

  private func reconnect() async {
    isCheckingConnection = true
    _ = await authViewModel.reconnect()
    isCheckingConnection = false
  }
}
