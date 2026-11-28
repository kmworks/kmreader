//
// ServerCardView.swift
//
//

import SwiftUI

/// Current-server summary card: display name, role badge, switch button,
/// account and server rows. Shown on the Server page
/// (iPad and macOS sidebar, tvOS).
struct ServerCardView: View {
  let authViewModel: AuthViewModel

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var endpointsModel = CurrentServerEndpointsModel()

  var body: some View {
    #if os(tvOS)
      // tvOS has no room for a nested button: the whole card is the switch
      // entry, so directional focus always has a full-width target.
      NavigationLink(value: NavDestination.settingsServers) {
        cardContent
      }
      .adaptiveButtonStyle(.plain)
    #else
      cardContent
    #endif
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(serverDisplayName)
              .font(.title2)
              .fontWeight(.semibold)

            if let roleLabel {
              Text(roleLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .foregroundColor(.secondary)
            }
          }
        }

        Spacer()

        #if os(tvOS)
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        #else
          HStack(spacing: 8) {
            ServerEndpointQuickSwitchMenu(model: endpointsModel, authViewModel: authViewModel)
            NavigationLink(value: NavDestination.settingsServers) {
              Label(String(localized: "server.switch"), systemImage: "arrow.left.arrow.right")
            }
            .font(.caption)
            .controlSize(.small)
            .adaptiveButtonStyle(.borderedProminent)
          }
        #endif
      }

      if let userEmail = accountDisplayValue {
        InfoRow(
          label: ServerSection.account.title,
          value: userEmail,
          icon: "person"
        )
      }

      InfoRow(
        label: String(localized: "Server"),
        value: ServerEndpoint.displayURL(
          for: current.serverURL.isEmpty ? current.serverDisplayName : current.serverURL),
        icon: "globe"
      )

    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .task(id: current.instanceId) {
      await endpointsModel.refresh()
    }
  }

  private var serverDisplayName: String {
    if !current.serverDisplayName.isEmpty {
      return current.serverDisplayName
    }
    return String(localized: "Server")
  }

  private var roleLabel: String? {
    guard accountDisplayValue != nil else { return nil }
    return current.isAdmin
      ? String(localized: "user.role.admin") : String(localized: "user.role.user")
  }

  private var accountDisplayValue: String? {
    if !current.username.isEmpty {
      return current.username
    }
    return nil
  }
}
