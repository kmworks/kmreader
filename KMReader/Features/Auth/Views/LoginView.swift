//
// LoginView.swift
//
//

import Foundation
import SwiftUI

struct LoginView: View {
  let authViewModel: AuthViewModel
  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isLoggedInV2") private var isLoggedIn: Bool = false
  @State private var serverURLText: String = ""
  @State private var usesHTTPS = true
  @State private var usernameText: String = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var apiKey = ""
  @State private var instanceName = ""
  @State private var autoCreateApiKey = true
  @State private var loginErrorMessage: String?
  @State private var authMethod: AuthenticationMethod = .basicAuth
  @State private var probeState: ProbeState = .idle

  var body: some View {
    ScrollView {
      VStack(spacing: 32) {
        headerSection
        formSection
      }
      .padding(16)
      #if os(tvOS)
        .frame(maxWidth: 800)
      #else
        .frame(maxWidth: 520)
      #endif
    }
    .task {
      let stored = current.serverURL.isEmpty ? "https://demo.komga.org" : current.serverURL
      if !absorbSchemePrefix(from: stored) {
        serverURLText = stored
      }
      usernameText = current.username
    }
    .task(id: serverURL) {
      await probeClaimStatus()
    }
  }

  private var serverURL: String {
    "\(usesHTTPS ? "https" : "http")://\(serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  private var isFormValid: Bool {
    guard !serverURLText.isEmpty else { return false }
    switch probeState {
    case .unclaimed:
      return isValidEmail(usernameText) && !password.isEmpty && password == confirmPassword
    case .claimed:
      switch authMethod {
      case .basicAuth:
        return !usernameText.isEmpty && !password.isEmpty
      case .apiKey:
        return !apiKey.isEmpty
      }
    case .idle, .probing, .failed:
      return false
    }
  }

  private func isValidEmail(_ email: String) -> Bool {
    email.wholeMatch(of: /^[^\s@]+@[^\s@]+\.[^\s@]+$/) != nil
  }

  // The field holds host[:port][/path] only; pasted full URLs donate their scheme to the toggle.
  @discardableResult
  private func absorbSchemePrefix(from text: String) -> Bool {
    for (prefix, secure) in [("https://", true), ("http://", false)] {
      if text.hasPrefix(prefix) {
        usesHTTPS = secure
        serverURLText = String(text.dropFirst(prefix.count))
        return true
      }
    }
    return false
  }

  private func probeClaimStatus() async {
    let serverURL = serverURL
    guard isCompleteServerURL(serverURL) else {
      probeState = .idle
      return
    }
    try? await Task.sleep(for: .milliseconds(500))
    guard !Task.isCancelled else { return }
    probeState = .probing
    do {
      let status = try await AuthService.probeClaimStatus(serverURL: serverURL)
      probeState = status.isClaimed ? .claimed : .unclaimed
    } catch {
      // Unreachable or non-Komga servers get no form, just the failure hint
      probeState = .failed
    }
  }

  // Partial input while typing must not fire requests; only a parseable host is probeable.
  private func isCompleteServerURL(_ string: String) -> Bool {
    guard let host = URLComponents(string: string)?.host else { return false }
    return !host.isEmpty
  }

  private func login() {
    Task {
      setLoginErrorMessage(nil)
      let trimmedName = instanceName.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayName = trimmedName.isEmpty ? nil : trimmedName

      do {
        if probeState == .unclaimed {
          _ = try await AuthService.claimServer(
            serverURL: serverURL, email: usernameText, password: password)
          try await authViewModel.login(
            username: usernameText,
            password: password,
            serverURL: serverURL,
            displayName: displayName,
            autoCreateApiKey: autoCreateApiKey
          )
        } else {
          switch authMethod {
          case .basicAuth:
            try await authViewModel.login(
              username: usernameText,
              password: password,
              serverURL: serverURL,
              displayName: displayName,
              autoCreateApiKey: autoCreateApiKey
            )
          case .apiKey:
            try await authViewModel.loginWithAPIKey(
              apiKey: apiKey,
              serverURL: serverURL,
              displayName: displayName
            )
          }
        }
        dismiss()
      } catch {
        setLoginErrorMessage(formattedErrorMessage(from: error))
      }
    }
  }

  private var headerSection: some View {
    VStack(spacing: 12) {
      Image("Komga")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 72)

      Text(String(localized: "Sign in to Komga"))
        .font(.system(size: 32, weight: .bold))
        .foregroundStyle(.primary)

      Text(String(localized: "Enter the credentials you use to access your Komga server."))
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }
  }

  private var formSection: some View {
    VStack(spacing: 20) {
      serverURLField

      switch probeState {
      case .idle:
        EmptyView()
      case .probing:
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(String(localized: "Checking server…"))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
      case .failed:
        errorHint(
          String(localized: "Could not connect to a Komga server. Check the address and try again.")
        )
        .transition(.opacity)
      case .claimed, .unclaimed:
        revealedForm
          .transition(.opacity)
      }
    }
    .animation(.appCurve(), value: authMethod)
    .animation(.appCurve(0.2), value: loginErrorMessage)
    .animation(.appCurve(0.2), value: probeState)
  }

  private var serverURLField: some View {
    FieldContainer(
      title: "Server URL",
      systemImage: "server.rack",
      containerBackground: fieldBackgroundColor
    ) {
      HStack(spacing: 8) {
        Text(usesHTTPS ? "https://" : "http://")
          .foregroundStyle(.secondary)
          .id(usesHTTPS)
          .transition(.opacity)
        TextField(String(localized: "Enter your server URL"), text: $serverURLText)
          .textContentType(.URL)
          #if os(iOS) || os(tvOS)
            .autocapitalization(.none)
            .keyboardType(.URL)
          #endif
          .autocorrectionDisabled()
          .onChange(of: serverURLText) { _, newValue in
            setLoginErrorMessage(nil)
            absorbSchemePrefix(from: newValue)
          }
        Button {
          usesHTTPS.toggle()
        } label: {
          Image(systemName: usesHTTPS ? "lock.fill" : "lock.open.fill")
            .foregroundStyle(usesHTTPS ? .green : .orange)
            .contentTransition(.symbolEffect(.replace))
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(usesHTTPS ? "HTTPS" : "HTTP")
      }
      .animation(.appCurve(0.15), value: usesHTTPS)
    }
  }

  private var revealedForm: some View {
    Group {
      FieldContainer(
        title: "Instance Name (Optional)",
        systemImage: "tag",
        containerBackground: fieldBackgroundColor
      ) {
        TextField(String(localized: "e.g. \"Home\" or \"Work\""), text: $instanceName)
          .autocorrectionDisabled()
      }

      if probeState == .unclaimed {
        Text(
          String(
            localized:
              "This server has not been initialized yet. Create the first administrator account to get started."
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

        FieldContainer(
          title: "Email",
          systemImage: "envelope",
          containerBackground: fieldBackgroundColor
        ) {
          TextField(String(localized: "Enter your email"), text: $usernameText)
            .textContentType(.emailAddress)
            #if os(iOS) || os(tvOS)
              .autocapitalization(.none)
              .keyboardType(.emailAddress)
            #endif
            .autocorrectionDisabled()
            .onChange(of: usernameText) { _, _ in
              setLoginErrorMessage(nil)
            }
        }

        FieldContainer(
          title: "Password",
          systemImage: "lock",
          containerBackground: fieldBackgroundColor
        ) {
          SecureField(String(localized: "Enter your password"), text: $password)
            .textContentType(.newPassword)
            .onChange(of: password) { _, _ in
              setLoginErrorMessage(nil)
            }
        }

        FieldContainer(
          title: "Confirm Password",
          systemImage: "lock",
          containerBackground: fieldBackgroundColor
        ) {
          SecureField(String(localized: "Confirm your password"), text: $confirmPassword)
            .textContentType(.newPassword)
            .onChange(of: confirmPassword) { _, _ in
              setLoginErrorMessage(nil)
            }
        }

        if !confirmPassword.isEmpty && confirmPassword != password {
          errorHint(String(localized: "Passwords do not match"))
        }
      } else {
        // Auth method picker
        Picker(String(localized: "Authentication Method"), selection: $authMethod) {
          Text(String(localized: "Username & Password")).tag(AuthenticationMethod.basicAuth)
          Text(String(localized: "API Key")).tag(AuthenticationMethod.apiKey)
        }
        .pickerStyle(.segmented)
        .onChange(of: authMethod) { _, _ in
          setLoginErrorMessage(nil)
        }

        // Conditional fields based on auth method
        switch authMethod {
        case .basicAuth:
          FieldContainer(
            title: "Username",
            systemImage: "person",
            containerBackground: fieldBackgroundColor
          ) {
            TextField(String(localized: "Enter your username"), text: $usernameText)
              .textContentType(.username)
              #if os(iOS) || os(tvOS)
                .autocapitalization(.none)
              #endif
              .autocorrectionDisabled()
              .onChange(of: usernameText) { _, _ in
                setLoginErrorMessage(nil)
              }
          }

          FieldContainer(
            title: "Password",
            systemImage: "lock",
            containerBackground: fieldBackgroundColor
          ) {
            SecureField(String(localized: "Enter your password"), text: $password)
              .textContentType(.password)
              .onChange(of: password) { _, _ in
                setLoginErrorMessage(nil)
              }
          }

        case .apiKey:
          FieldContainer(
            title: "API Key",
            systemImage: "key",
            containerBackground: fieldBackgroundColor
          ) {
            SecureField(String(localized: "Enter your API Key"), text: $apiKey)
              .textContentType(.password)
              #if os(iOS) || os(tvOS)
                .autocapitalization(.none)
              #endif
              .autocorrectionDisabled()
              .onChange(of: apiKey) { _, _ in
                setLoginErrorMessage(nil)
              }
          }
        }
      }

      if probeState == .unclaimed || authMethod == .basicAuth {
        Toggle(isOn: $autoCreateApiKey) {
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Auto-create API Key"))
              .font(.callout)
            Text(
              String(
                localized:
                  "Replace password authentication with a generated API key that never expires."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if let loginErrorMessage {
        errorHint(loginErrorMessage)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      Button(action: login) {
        HStack(spacing: 8) {
          if authViewModel.isLoading {
            LoadingIcon()
          } else {
            if probeState == .unclaimed {
              Text(String(localized: "Create Account"))
            } else {
              Text(String(localized: "Login"))
            }
            Image(systemName: "arrow.right.circle.fill")
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
      }
      #if os(iOS) || os(macOS)
        .frame(maxWidth: 360)
      #endif
      .frame(maxWidth: .infinity, alignment: .center)
      .adaptiveButtonStyle(.borderedProminent)
      .disabled(!isFormValid || authViewModel.isLoading)
      .padding(.top, 8)
    }
  }

  private func errorHint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
      Text(text)
        .font(.footnote)
        .foregroundStyle(.red)
        .multilineTextAlignment(.leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 4)
  }

  private func setLoginErrorMessage(_ message: String?) {
    guard loginErrorMessage != message else { return }
    withAnimation(.appCurve(0.2)) {
      loginErrorMessage = message
    }
  }

  private var fieldBackgroundColor: Color {
    #if os(macOS)
      Color(nsColor: .textBackgroundColor)
    #elseif os(iOS)
      Color(.secondarySystemBackground)
    #else
      Color.white.opacity(0.08)
    #endif
  }

  private func formattedErrorMessage(from error: Error) -> String {
    if let apiError = error as? APIError {
      return apiError.description
    }
    if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
      return message
    }
    return error.localizedDescription
  }
}

private struct FieldContainer<Content: View>: View {
  let title: LocalizedStringKey
  let systemImage: String
  let containerBackground: Color
  private let content: Content

  init(
    title: LocalizedStringKey,
    systemImage: String,
    containerBackground: Color,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.containerBackground = containerBackground
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: systemImage)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      content
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(containerBackground)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.primary.opacity(0.05))
        )
    }
  }
}

private enum ProbeState {
  case idle
  case probing
  case claimed
  case unclaimed
  case failed
}
