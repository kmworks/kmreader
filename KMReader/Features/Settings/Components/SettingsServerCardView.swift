//
// SettingsServerCardView.swift
//
//

import SwiftUI

/// Current-server summary shown at the top of the iPhone Settings page.
/// The whole card is a link to the server list, following the Apple ID card
/// idiom from iOS Settings: a colored server badge, the server name, and the
/// account/URL as secondary lines (the URL line carries inline reachability
/// and latency without adding a fourth line). Account roles live on the
/// Account page.
struct SettingsServerCardView: View {
  let authViewModel: AuthViewModel

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var endpointsModel = CurrentServerEndpointsModel()

  var body: some View {
    NavigationLink(value: NavDestination.settingsServers) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          Image(systemName: "server.rack")
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.serverGreen)
            .frame(width: 44, height: 44)
            .background(
              Color.serverGreen.opacity(0.15),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

          VStack(alignment: .leading, spacing: 2) {
            Text(serverDisplayName)
              .font(.headline)
            if !current.username.isEmpty {
              Text(current.username)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            ServerEndpointURLLabel(
              url: current.serverURL.isEmpty ? current.serverDisplayName : current.serverURL,
              status: activeStatus
            )
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

      }
      .contentShape(Rectangle())
    }
    .adaptiveButtonStyle(.plain)
    .contextMenu {
      if endpointsModel.hasMultipleEndpoints, let instance = endpointsModel.instance {
        ForEach(instance.endpoints) { endpoint in
          Button {
            endpointsModel.switchEndpoint(endpoint, using: authViewModel)
          } label: {
            if endpointsModel.isActive(endpoint) {
              Label(endpoint.displayName, systemImage: "checkmark")
            } else {
              Text(endpoint.displayName)
            }
          }
          .disabled(endpointsModel.isActive(endpoint))
        }
      }
    }
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

  private var activeStatus: ServerEndpointProbeStatus? {
    guard let active = endpointsModel.activeEndpoint else { return nil }
    return endpointsModel.status(for: active)
  }
}
