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

  #if os(tvOS)
    @State private var requestTimeoutText = ""
    @State private var downloadTimeoutText = ""
    @State private var authTimeoutText = ""

    private var requestTimeoutTextBinding: Binding<String> {
      Binding(
        get: { requestTimeoutText.isEmpty ? "\(Int(requestTimeout))" : requestTimeoutText },
        set: { newValue in
          requestTimeoutText = newValue
          if let value = Int(newValue), value >= 1 {
            requestTimeout = Double(value)
          }
        }
      )
    }

    private var downloadTimeoutTextBinding: Binding<String> {
      Binding(
        get: { downloadTimeoutText.isEmpty ? "\(Int(downloadTimeout))" : downloadTimeoutText },
        set: { newValue in
          downloadTimeoutText = newValue
          if let value = Int(newValue), value >= 1 {
            downloadTimeout = Double(value)
          }
        }
      )
    }

    private var authTimeoutTextBinding: Binding<String> {
      Binding(
        get: { authTimeoutText.isEmpty ? "\(Int(authTimeout))" : authTimeoutText },
        set: { newValue in
          authTimeoutText = newValue
          if let value = Int(newValue), value >= 1 {
            authTimeout = Double(value)
          }
        }
      )
    }

    private var isRequestTimeoutTextValid: Bool {
      requestTimeoutText.isEmpty || (Int(requestTimeoutText).map { $0 >= 1 } ?? false)
    }

    private var isDownloadTimeoutTextValid: Bool {
      downloadTimeoutText.isEmpty || (Int(downloadTimeoutText).map { $0 >= 1 } ?? false)
    }

    private var isAuthTimeoutTextValid: Bool {
      authTimeoutText.isEmpty || (Int(authTimeoutText).map { $0 >= 1 } ?? false)
    }
  #endif

  var body: some View {
    Form {
      Section(header: Text(String(localized: "settings.network.general"))) {
        #if os(tvOS)
          timeoutRow(
            label: "settings.network.request_timeout.label",
            description: "settings.network.request_timeout.description",
            text: requestTimeoutTextBinding,
            isValid: isRequestTimeoutTextValid
          )

          timeoutRow(
            label: "settings.network.download_timeout.label",
            description: "settings.network.download_timeout.description",
            text: downloadTimeoutTextBinding,
            isValid: isDownloadTimeoutTextValid
          )

          timeoutRow(
            label: "settings.network.auth_timeout.label",
            description: "settings.network.auth_timeout.description",
            text: authTimeoutTextBinding,
            isValid: isAuthTimeoutTextValid
          )
        #else
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
        #endif

        retryCountRow
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(SettingsSection.network.title)
  }

  private var retryCountRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      #if os(tvOS)
        HStack {
          Label(
            String(localized: "settings.network.api_retry_count.label"),
            systemImage: "arrow.counterclockwise")
          Spacer()
          Button {
            apiRetryCount = max(0, apiRetryCount - 1)
          } label: {
            Image(systemName: "minus")
          }
          .disabled(apiRetryCount <= 0)
          Text("\(apiRetryCount)")
            .foregroundStyle(.secondary)
            .frame(minWidth: 24)
          Button {
            apiRetryCount = min(5, apiRetryCount + 1)
          } label: {
            Image(systemName: "plus")
          }
          .disabled(apiRetryCount >= 5)
        }
        .adaptiveButtonStyle(.bordered)
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

  #if os(tvOS)
    @ViewBuilder
    private func timeoutRow(
      label: LocalizedStringResource,
      description: LocalizedStringResource,
      text: Binding<String>,
      isValid: Bool
    ) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label {
            Text(label)
          } icon: {
            Image(systemName: "clock")
          }
          Spacer()
          TextField(String(localized: "Timeout Seconds"), text: text)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 160)
            .foregroundStyle(isValid ? Color.primary : Color.red)
          Text("s")
            .foregroundStyle(.secondary)
        }
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  #else
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
          #if os(macOS)
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
  #endif
}
