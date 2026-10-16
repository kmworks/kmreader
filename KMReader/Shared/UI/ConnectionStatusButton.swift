//
// ConnectionStatusButton.swift
//
//

import SwiftUI

struct ConnectionStatusButton: View {
  let authViewModel: AuthViewModel
  let onReconnected: (() -> Void)?

  init(authViewModel: AuthViewModel, onReconnected: (() -> Void)? = nil) {
    self.authViewModel = authViewModel
    self.onReconnected = onReconnected
  }

  @AppStorage("isOffline") private var isOffline: Bool = false

  private var isCheckingConnection: Bool {
    authViewModel.bootstrapState == .validating
  }

  private var connectionStatusColor: Color {
    if isCheckingConnection {
      return .orange
    }
    return isOffline ? .red : .green
  }

  private var actionTitle: String {
    if isOffline {
      return String(localized: "Reconnect")
    }
    return String(localized: "Enter Offline Mode")
  }

  var body: some View {
    Button {
      if isOffline {
        Task {
          await reconnect()
        }
      } else {
        authViewModel.enterOfflineMode()
      }
    } label: {
      Image(systemName: isOffline ? AppIcon.connectionOffline : AppIcon.connectionOnline)
        .foregroundStyle(connectionStatusColor)
        .contentShape(Rectangle())
        .symbolEffect(.pulse, options: .repeating, isActive: isCheckingConnection)
    }
    .disabled(isCheckingConnection)
    .accessibilityLabel(actionTitle)
    .help(actionTitle)
  }

  private func reconnect() async {
    let reconnected = await authViewModel.reconnect()
    if reconnected {
      onReconnected?()
    }
  }
}
