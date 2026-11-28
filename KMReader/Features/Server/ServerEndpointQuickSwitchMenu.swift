//
// ServerEndpointQuickSwitchMenu.swift
//

import SwiftUI

struct ServerEndpointQuickSwitchMenu: View {
  let model: CurrentServerEndpointsModel
  let authViewModel: AuthViewModel

  var body: some View {
    if let active = model.activeEndpoint {
      if model.hasMultipleEndpoints {
        Menu {
          endpointMenuItems
        } label: {
          HStack(spacing: 4) {
            if model.status(for: active) != nil {
              ServerEndpointStatusLabel(status: model.status(for: active))
            } else {
              Text(verbatim: "—")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
          .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
      } else {
        ServerEndpointStatusLabel(status: model.status(for: active))
      }
    }
  }

  @ViewBuilder
  private var endpointMenuItems: some View {
    if let instance = model.instance {
      ForEach(instance.endpoints) { endpoint in
        Button {
          model.switchEndpoint(endpoint, using: authViewModel)
        } label: {
          if model.isActive(endpoint) {
            Label(menuTitle(for: endpoint), systemImage: "checkmark")
          } else {
            Text(menuTitle(for: endpoint))
          }
        }
        .disabled(model.isActive(endpoint))
      }

      Divider()

      Button {
        model.probe()
      } label: {
        Label(String(localized: "Refresh Status"), systemImage: "arrow.clockwise")
      }
    }
  }

  private func menuTitle(for endpoint: ServerEndpoint) -> String {
    switch model.status(for: endpoint) {
    case .reachable(let milliseconds):
      return "\(endpoint.displayName) (\(milliseconds) ms)"
    case .unauthorized:
      return "\(endpoint.displayName) (\(String(localized: "Auth Failed")))"
    case .unreachable:
      return "\(endpoint.displayName) (\(String(localized: "Unreachable")))"
    case .checking, nil:
      return endpoint.displayName
    }
  }
}
