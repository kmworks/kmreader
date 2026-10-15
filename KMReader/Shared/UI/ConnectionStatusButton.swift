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
  @State private var isCheckingConnection = false

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
      if isCheckingConnection {
        LoadingIcon()
      } else {
        Image(systemName: isOffline ? AppIcon.connectionOffline : AppIcon.connectionOnline)
          .foregroundStyle(isOffline ? .red : .green)
          .contentShape(Rectangle())
      }
    }
    .disabled(isCheckingConnection)
    .accessibilityLabel(actionTitle)
    .help(actionTitle)
  }

  private func reconnect() async {
    isCheckingConnection = true
    let reconnected = await authViewModel.reconnect()
    isCheckingConnection = false
    if reconnected {
      onReconnected?()
    }
  }
}
