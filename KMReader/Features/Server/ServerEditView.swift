//
// ServerEditView.swift
//
//

import SwiftUI

struct ServerEditView: View {
  let authViewModel: AuthViewModel
  let instance: ServerDisplayItem
  let onSaved: () -> Void

  private let logger = AppLogger(.auth)

  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var name: String
  @State private var serverURL: String
  @State private var username: String
  @State private var password: String = ""
  @State private var apiKey: String = ""
  @State private var authMethod: AuthenticationMethod
  @State private var autoCreateApiKey = true
  @State private var protected: Bool
  @State private var isValidating = false
  @State private var isSaving = false
  @State private var validationMessage: String?
  @State private var isValidated = false

  private enum ValidationStatus: Equatable {
    case success(String)
    case error(String)
    case none
  }

  private var validationStatus: ValidationStatus {
    guard let message = validationMessage else {
      return .none
    }
    if isValidated {
      return .success(message)
    } else {
      return .error(message)
    }
  }

  init(instance: ServerDisplayItem, authViewModel: AuthViewModel, onSaved: @escaping () -> Void) {
    self.instance = instance
    self.authViewModel = authViewModel
    self.onSaved = onSaved
    _name = State(initialValue: instance.name)
    _serverURL = State(initialValue: instance.serverURL)
    _username = State(initialValue: instance.username)
    _authMethod = State(initialValue: instance.authMethod)
    _protected = State(initialValue: instance.protected)
    if instance.authMethod == .apiKey {
      _apiKey = State(initialValue: instance.authToken)
    }
  }

  var body: some View {
    SheetView(title: String(localized: "Edit Server"), size: .large, applyFormStyle: true) {
      Form {
        Section(header: Text("Display")) {
          TextField("Name", text: $name)
        }

        Section(header: Text("Server")) {
          TextField("Server URL", text: $serverURL)
            .textContentType(.URL)
            #if os(iOS) || os(tvOS)
              .textInputAutocapitalization(.never)
              .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
            .onChange(of: serverURL) { _, _ in
              resetValidation()
            }
        }

        Section(
          header: Text("Credentials"),
          footer: Group {
            switch validationStatus {
            case .success(let message):
              HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption)
                Text(message)
                  .foregroundStyle(.green)
                  .font(.caption)
              }
            case .error(let message):
              HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.red)
                  .font(.caption)
                Text(message)
                  .foregroundStyle(.red)
                  .font(.caption)
              }
            case .none:
              if authMethod == .basicAuth {
                Text(
                  String(localized: "Leave the password empty to keep the existing credentials.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          }
        ) {
          Picker(String(localized: "Authentication Method"), selection: authMethodBinding) {
            Text(String(localized: "Username & Password")).tag(AuthenticationMethod.basicAuth)
            Text(String(localized: "API Key")).tag(AuthenticationMethod.apiKey)
          }
          .pickerStyle(.segmented)

          if authMethod == .basicAuth {
            TextField(String(localized: "Username"), text: $username)
              .textContentType(.username)
              #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
              #endif
              .autocorrectionDisabled()
              .onChange(of: username) { _, _ in
                resetValidation()
              }

            SecureField(String(localized: "Password"), text: $password)
              .textContentType(.password)
              .onChange(of: password) { _, _ in
                resetValidation()
              }

            Toggle(isOn: $autoCreateApiKey) {
              VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Auto-create API Key"))
                Text(
                  String(
                    localized:
                      "When a new password is set, replace it with a generated API key that never expires."
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          } else {
            SecureField(String(localized: "API Key"), text: $apiKey)
              .textContentType(.password)
              #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
              #endif
              .autocorrectionDisabled()
              .onChange(of: apiKey) { _, _ in
                resetValidation()
              }
          }

          Button {
            validateConnection()
          } label: {
            HStack {
              if isValidating {
                LoadingIcon()
              } else {
                Image(systemName: "checkmark.circle")
              }
              Text(String(localized: "Validate Connection"))
            }
            .frame(maxWidth: .infinity)
          }
          .adaptiveButtonStyle(.bordered)
          .disabled(isValidating || !canValidate)
        }

        Section(header: Text(String(localized: "Privacy"))) {
          Toggle(isOn: $protected) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "Protected Server"))
              Text(
                String(
                  localized:
                    "Hide this server from the normal server list and require device authentication before switching to it."
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .disabled(!LocalDeviceAuthenticationService.shared.canAuthenticate && !protected)
        }
      }
      #if os(tvOS)
        .focusSection()
      #endif
    } controls: {
      Button {
        saveChanges()
      } label: {
        if isSaving {
          LoadingIcon()
        } else {
          Label(String(localized: "Save"), systemImage: "checkmark")
        }
      }
      .disabled(!canSave)
    }
  }

  private var authMethodBinding: Binding<AuthenticationMethod> {
    Binding(
      get: { authMethod },
      set: { newValue in
        withAnimation {
          authMethod = newValue
          clearValidation()
        }
      }
    )
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedServerURL: String {
    // Full normalization (not just whitespace): a trailing slash saved to
    // the instance row would resurface as `//api/...` request URLs when
    // this server is switched to. Also makes editing a legacy slashed row
    // register as a change, so saving it heals the persisted value.
    Current.normalizeServerURL(serverURL)
  }

  private var trimmedUsername: String {
    username.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var hasChanges: Bool {
    if trimmedName != instance.name || trimmedServerURL != instance.serverURL
      || authMethod != instance.authMethod || protected != instance.protected
    {
      return true
    }
    if authMethod == .basicAuth {
      return trimmedUsername != instance.username || !password.isEmpty
    } else {
      return apiKey != instance.authToken
    }
  }

  private var canSave: Bool {
    guard !isSaving else { return false }
    guard !trimmedServerURL.isEmpty else { return false }

    if authMethod == .basicAuth {
      guard !trimmedUsername.isEmpty else { return false }
    } else {
      guard !apiKey.isEmpty else { return false }
    }

    // If no changes, disable save
    guard hasChanges else {
      return false
    }

    // If only name changed, allow save without validation
    let isCredsChanged: Bool
    if authMethod == .basicAuth {
      isCredsChanged =
        trimmedServerURL != instance.serverURL || trimmedUsername != instance.username
        || !password.isEmpty || authMethod != instance.authMethod
    } else {
      isCredsChanged =
        trimmedServerURL != instance.serverURL || apiKey != instance.authToken
        || authMethod != instance.authMethod
    }

    if isCredsChanged {
      return isValidated
    }

    return true
  }

  private var canValidate: Bool {
    guard !trimmedServerURL.isEmpty else { return false }

    if authMethod == .basicAuth {
      guard !trimmedUsername.isEmpty else { return false }
      // Can validate if password is provided
      if !password.isEmpty { return true }
      // If password is empty, can only validate if only serverURL changed (username unchanged)
      // If username changed, password must be provided
      return trimmedServerURL != instance.serverURL && trimmedUsername == instance.username
        && instance.authMethod == .basicAuth
    } else {
      return !apiKey.isEmpty
    }
  }

  private func saveChanges() {
    guard canSave else {
      return
    }
    guard !protected || LocalDeviceAuthenticationService.shared.canAuthenticate else {
      ErrorManager.shared.notify(
        message: String(localized: "Device authentication is not available on this device."))
      return
    }

    let resolvedName =
      trimmedName.isEmpty
      ? defaultInstanceName(serverURL: trimmedServerURL)
      : trimmedName

    let resolvedAuthToken: String
    if authMethod == .basicAuth {
      if !password.isEmpty {
        guard let token = makeAuthToken(username: trimmedUsername, password: password) else {
          ErrorManager.shared.notify(
            message: String(localized: "notification.settings.encodeCredentialsFailed"))
          return
        }
        resolvedAuthToken = token
      } else {
        resolvedAuthToken = instance.authToken
      }
    } else {
      resolvedAuthToken = apiKey
    }

    withAnimation {
      isSaving = true
    }

    Task {
      if protected != instance.protected {
        let authenticated = await LocalDeviceAuthenticationService.shared.authenticateProtectedAccess(
          reason: String(localized: "Authenticate to change protection for this server.")
        )
        guard authenticated else {
          withAnimation {
            isSaving = false
          }
          return
        }
      }

      do {
        var finalAuthToken = resolvedAuthToken
        var finalAuthMethod = authMethod
        var finalApiKeyId: String?
        if authMethod == .basicAuth, !password.isEmpty, autoCreateApiKey {
          let comment = ApiKey.appManagedComment(deviceName: PlatformHelper.deviceName)
          do {
            let createdKey = try await AuthService.createApiKey(
              serverURL: trimmedServerURL,
              authToken: resolvedAuthToken,
              comment: comment
            )
            finalAuthToken = createdKey.key
            finalAuthMethod = .apiKey
            finalApiKeyId = createdKey.id
            await AuthService.deleteStaleAppManagedKeys(
              serverURL: trimmedServerURL,
              authToken: createdKey.key,
              comment: comment,
              keeping: createdKey.id
            )
          } catch {
            logger.warning(
              "⚠️ API key creation failed, keeping password authentication for \(trimmedServerURL): \(error.diagnosticDescription)"
            )
          }
        }

        let database = try await DatabaseOperator.database()
        guard
          let updatedInstance = try await database.updateServerDisplayItem(
            id: instance.id,
            name: resolvedName,
            serverURL: trimmedServerURL,
            username: trimmedUsername,
            authToken: finalAuthToken,
            authMethod: finalAuthMethod,
            apiKeyId: finalApiKeyId,
            protected: protected
          )
        else {
          withAnimation {
            isSaving = false
          }
          return
        }
        withAnimation {
          isSaving = false
        }

        if current.instanceId == updatedInstance.instanceId {
          Task {
            _ = await authViewModel.switchTo(instance: updatedInstance)
          }
        }

        onSaved()
        dismiss()
      } catch {
        withAnimation {
          isSaving = false
        }
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func makeAuthToken(username: String, password: String) -> String? {
    let credentials = "\(username):\(password)"
    return credentials.data(using: .utf8)?.base64EncodedString()
  }

  private func resetValidation() {
    withAnimation {
      clearValidation()
    }
  }

  private func clearValidation() {
    isValidated = false
    validationMessage = nil
  }

  private func validateConnection() {
    guard canValidate else {
      return
    }

    // Determine which authToken/credentials to use for validation
    let tokenToTest: String
    if authMethod == .basicAuth {
      if !password.isEmpty {
        guard let token = makeAuthToken(username: trimmedUsername, password: password) else {
          withAnimation {
            validationMessage = String(localized: "Unable to encode credentials")
            isValidated = false
          }
          return
        }
        tokenToTest = token
      } else {
        // Reuse existing token
        tokenToTest = instance.authToken
      }
    } else {
      tokenToTest = apiKey
    }

    withAnimation {
      isValidating = true
      validationMessage = nil
      isValidated = false
    }

    Task {
      do {
        // We validate and get the user.
        // If API Key, this will return the user associated with the key.
        let user = try await authViewModel.testCredentials(
          serverURL: trimmedServerURL,
          authToken: tokenToTest,
          authMethod: authMethod
        )

        withAnimation {
          validationMessage = String(localized: "Connection validated successfully")
          isValidated = true
          isValidating = false

          // Update username if using API Key so it's correct when saving
          if authMethod == .apiKey {
            self.username = user.email
          }
        }
      } catch {
        let message: String
        if let apiError = error as? APIError {
          switch apiError {
          case .unauthorized:
            message = String(localized: "Invalid credentials")
          case .networkError:
            message = String(localized: "Network error - check server URL")
          default:
            message = String(localized: "Validation failed: \(apiError.localizedDescription)")
          }
        } else {
          message = String(localized: "Validation failed: \(error.localizedDescription)")
        }
        withAnimation {
          validationMessage = message
          isValidated = false
          isValidating = false
        }
      }
    }
  }

  private func defaultInstanceName(serverURL: String) -> String {
    if let host = URL(string: serverURL)?.host, !host.isEmpty {
      return host
    }
    return serverURL
  }
}
