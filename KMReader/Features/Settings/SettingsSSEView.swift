//
// SettingsSSEView.swift
//
//

import SwiftUI

struct SettingsSSEView: View {
  @AppStorage("enableSSE") private var enableSSE: Bool = true
  @AppStorage("enableSSENotify") private var enableSSENotify: Bool = false
  @AppStorage("enableSSEAutoRefresh") private var enableSSEAutoRefresh: Bool = true
  @AppStorage("isLoggedInV2") private var isLoggedIn: Bool = false

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $enableSSE) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Image(systemName: "antenna.radiowaves.left.and.right")
              Text(String(localized: "Real-time Updates"))
            }
            Text(String(localized: "Enable Server-Sent Events for real-time updates"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .onChange(of: enableSSE) { _, newValue in
          Task {
            // Always disconnect first to ensure clean state
            await SSEService.shared.disconnect()
            // Then connect if enabled and logged in
            if newValue && isLoggedIn {
              await SSEService.shared.connect()
            }
          }
        }
      } header: {
        Text(String(localized: "Connection"))
      } footer: {
        Text(
          String(
            localized:
              "Real-time updates allow the app to automatically refresh when content changes on the server."
          )
        )
      }

      Section {
        Toggle(isOn: $enableSSEAutoRefresh) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Image(systemName: "arrow.clockwise")
              Text(String(localized: "Auto-refresh Dashboard"))
            }
            Text(String(localized: "Automatically refresh dashboard when content changes"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .disabled(!enableSSE)
      } header: {
        Text(String(localized: "Auto-refresh"))
      } footer: {
        Text(
          enableSSE
            ? String(
              localized:
                "When disabled, the dashboard will not automatically refresh when SSE events are received. You can still manually refresh."
            )
            : String(localized: "Enable Real-time Updates above to use this feature.")
        )
      }

      Section {
        Toggle(isOn: $enableSSENotify) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Image(systemName: "bell")
              Text(String(localized: "Show Notifications"))
            }
            Text(String(localized: "Show connection status and task completion notifications"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .disabled(!enableSSE)
      } header: {
        Text(String(localized: "Notifications"))
      } footer: {
        Text(
          enableSSE
            ? String(
              localized:
                "When disabled, connection status and task completion messages will not be shown."
            )
            : String(localized: "Enable Real-time Updates above to use this feature.")
        )
      }
    }
    .formStyle(.grouped)
    .settingsFormWidth()
    .platformNavigationTitle(SettingsSection.sse.title)
  }
}
