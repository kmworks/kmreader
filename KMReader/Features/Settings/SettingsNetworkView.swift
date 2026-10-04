//
// SettingsNetworkView.swift
//
//

import SwiftUI

struct SettingsNetworkView: View {
  @AppStorage("requestTimeout") private var requestTimeout: Double = 15
  @AppStorage("downloadTimeout") private var downloadTimeout: Double = 60
  @AppStorage("authTimeout") private var authTimeout: Double = 5
  @AppStorage("apiRetryCount") private var apiRetryCount: Int = 0

  var body: some View {
    Form {
      Section(header: Text(String(localized: "settings.network.general"))) {
        timeoutRow(
          label: "settings.network.request_timeout.label",
          description: "settings.network.request_timeout.description",
          value: $requestTimeout
        )

        timeoutRow(
          label: "settings.network.download_timeout.label",
          description: "settings.network.download_timeout.description",
          value: $downloadTimeout
        )

        timeoutRow(
          label: "settings.network.auth_timeout.label",
          description: "settings.network.auth_timeout.description",
          value: $authTimeout
        )

        VStack(alignment: .leading, spacing: 8) {
          #if os(tvOS)
            HStack {
              Label(
                String(localized: "settings.network.api_retry_count.label"),
                systemImage: "arrow.counterclockwise")
              Spacer()
              Text("\(apiRetryCount)")
                .foregroundStyle(.secondary)
            }
          #else
            Stepper(value: $apiRetryCount, in: 0...5) {
              HStack {
                Label(
                  String(localized: "settings.network.api_retry_count.label"),
                  systemImage: "arrow.counterclockwise")
                Spacer()
                Text("\(apiRetryCount)")
                  .foregroundStyle(.secondary)
              }
            }
          #endif
          Text(String(localized: "settings.network.api_retry_count.description"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .settingsFormWidth()
    .platformNavigationTitle(SettingsSection.network.title)
  }

  @ViewBuilder
  private func timeoutRow(
    label: LocalizedStringResource,
    description: LocalizedStringResource,
    value: Binding<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label {
          Text(label)
        } icon: {
          Image(systemName: "clock")
        }
        Spacer()
        #if os(tvOS)
          Text("\(Int(value.wrappedValue))s")
            .foregroundStyle(.secondary)
        #elseif os(macOS)
          TextField("", value: value, format: .number)
            .multilineTextAlignment(.trailing)
            .frame(width: 50)
          Text("s")
            .foregroundStyle(.secondary)
        #else
          TextField(String(localized: "Timeout Seconds"), value: value, format: .number)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .frame(width: 50)
          Text("s")
            .foregroundStyle(.secondary)
        #endif
      }
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
