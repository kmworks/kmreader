//
// ServerView.swift
//
//

import Flow
import SwiftUI

struct ServerView: View {
  let authViewModel: AuthViewModel
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()
  @State private var showingUpdatePassword = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        ServerCardView()
        if current.isAdmin {
          managementSection
        }
        accountSection
      }
      .padding(.horizontal)
      .padding(.vertical, 12)
    }
    .platformNavigationTitle(String(localized: "tab.server"))
  }

  private var managementSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "Management"))
        .font(.headline)

      LazyVGrid(columns: actionColumns, spacing: actionGridSpacing) {
        NavigationLink(value: NavDestination.settingsLibraries) {
          ServerActionTile(
            title: ServerSection.libraries.title,
            systemImage: ServerSection.libraries.icon,
            color: ServerSection.libraries.color
          )
        }
        .adaptiveButtonStyle(.plain)

        NavigationLink(value: NavDestination.settingsServerInfo) {
          ServerActionTile(
            title: ServerSection.serverInfo.title,
            systemImage: ServerSection.serverInfo.icon,
            color: ServerSection.serverInfo.color
          )
        }
        .adaptiveButtonStyle(.plain)

        NavigationLink(value: NavDestination.settingsTasks) {
          ServerActionTile(
            title: ServerSection.tasks.title,
            systemImage: ServerSection.tasks.icon,
            color: ServerSection.tasks.color,
            badge: taskQueueStatus.count > 0 ? "\(taskQueueStatus.count)" : nil,
            badgeColor: Color.secondary
          )
        }
        .adaptiveButtonStyle(.plain)

        NavigationLink(value: NavDestination.settingsHistory) {
          ServerActionTile(
            title: ServerSection.history.title,
            systemImage: ServerSection.history.icon,
            color: ServerSection.history.color
          )
        }
        .adaptiveButtonStyle(.plain)

        NavigationLink(value: NavDestination.settingsMedia) {
          ServerActionTile(
            title: ServerSection.media.title,
            systemImage: ServerSection.media.icon,
            color: ServerSection.media.color
          )
        }
        .adaptiveButtonStyle(.plain)
      }
    }
  }

  private var accountSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(ServerSection.account.title)
        .font(.headline)

      accountDetailsCard

      LazyVGrid(columns: actionColumns, spacing: actionGridSpacing) {
        if !current.userId.isEmpty {
          Button {
            showingUpdatePassword = true
          } label: {
            ServerActionTile(
              title: String(localized: "account.details.changePassword"),
              systemImage: "key",
              color: .orange
            )
          }
          .adaptiveButtonStyle(.plain)
        }

        NavigationLink(value: NavDestination.settingsApiKey) {
          ServerActionTile(
            title: ServerSection.apiKeys.title,
            systemImage: ServerSection.apiKeys.icon,
            color: ServerSection.apiKeys.color
          )
        }
        .adaptiveButtonStyle(.plain)

        NavigationLink(value: NavDestination.settingsAuthenticationActivity) {
          ServerActionTile(
            title: ServerSection.authenticationActivity.title,
            systemImage: ServerSection.authenticationActivity.icon,
            color: ServerSection.authenticationActivity.color
          )
        }
        .adaptiveButtonStyle(.plain)
      }
    }
  }

  private var accountDetailsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(String(localized: "User"))
            .font(.caption)
            .foregroundColor(.secondary)

          if !current.username.isEmpty {
            Text(current.username)
              .font(.headline)
              .lineLimit(2)
          }
        }
      }

      if !current.userRoles.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(String(localized: "Roles"))
            .font(.caption)
            .foregroundColor(.secondary)

          HFlow(spacing: 8) {
            ForEach(current.userRoles, id: \.self) { role in
              RoleBadge(role: role)
            }
          }
        }
      } else if !current.userId.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(String(localized: "Roles"))
            .font(.caption)
            .foregroundColor(.secondary)

          Text(String(localized: "user.role.none"))
            .foregroundColor(.secondary)
            .italic()
        }
      }

    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .sheet(isPresented: $showingUpdatePassword) {
      UpdatePasswordSheet(authViewModel: authViewModel)
        .presentationDetents([.medium])
    }
  }

  private var actionGridSpacing: CGFloat {
    #if os(tvOS)
      return 24
    #else
      return 12
    #endif
  }

  private var actionColumns: [GridItem] {
    #if os(tvOS)
      return [
        GridItem(
          .adaptive(minimum: 360, maximum: 480),
          spacing: actionGridSpacing
        )
      ]
    #else
      return [GridItem(.adaptive(minimum: 160), spacing: actionGridSpacing)]
    #endif
  }
}
