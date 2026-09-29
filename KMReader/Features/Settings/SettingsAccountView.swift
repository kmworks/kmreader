//
// SettingsAccountView.swift
//
//

import Flow
import SwiftUI

/// iPhone-only sub-page holding the account entries that live in the
/// Server tab on larger platforms.
struct SettingsAccountView: View {
  let authViewModel: AuthViewModel

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var showingUpdatePassword = false

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center) {
            Image(systemName: "person.crop.circle.fill")
              .font(.system(size: 44))
              .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
              Text(current.username.isEmpty ? String(localized: "User") : current.username)
                .font(.headline)
              if current.isAdmin {
                Text(String(localized: "Admin"))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          if !current.userRoles.isEmpty {
            HFlow(spacing: 6) {
              ForEach(current.userRoles, id: \.self) { role in
                RoleBadge(role: role)
              }
            }
          } else if !current.userId.isEmpty {
            Text(String(localized: "user.role.none"))
              .font(.footnote)
              .foregroundColor(.secondary)
              .italic()
          }
        }
        .padding(.vertical, 4)
      }

      Section {
        if !current.userId.isEmpty {
          Button {
            showingUpdatePassword = true
          } label: {
            HStack {
              SettingsBadgeRow(
                title: String(localized: "account.details.changePassword"),
                icon: "key",
                color: .orange
              )
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          .adaptiveButtonStyle(.plain)
        }
        NavigationLink(value: NavDestination.settingsApiKey) {
          SettingsBadgeRow(
            title: ServerSection.apiKeys.title,
            icon: ServerSection.apiKeys.icon,
            color: ServerSection.apiKeys.color
          )
        }
        NavigationLink(value: NavDestination.settingsAuthenticationActivity) {
          SettingsBadgeRow(
            title: ServerSection.authenticationActivity.title,
            icon: ServerSection.authenticationActivity.icon,
            color: ServerSection.authenticationActivity.color
          )
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(ServerSection.account.title)
    .sheet(isPresented: $showingUpdatePassword) {
      UpdatePasswordSheet(authViewModel: authViewModel)
        .presentationDetents([.medium])
    }
  }
}
