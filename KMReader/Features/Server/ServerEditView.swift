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
  @State private var endpoints: [ServerEndpoint]
  @State private var activeEndpointID: UUID
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
    let initialEndpoints =
      instance.endpoints.isEmpty
      ? [ServerEndpoint(url: instance.serverURL)]
      : instance.endpoints
    let active =
      initialEndpoints.first(where: {
        $0.normalizedURL == Current.normalizeServerURL(instance.serverURL)
      }) ?? initialEndpoints[0]
    _name = State(initialValue: instance.name)
    _endpoints = State(initialValue: initialEndpoints)
    _activeEndpointID = State(initialValue: active.id)
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

        Section(
          header: Text(String(localized: "Server Addresses")),
          footer: VStack(alignment: .leading, spacing: 6) {
            if hasDuplicateEndpoints {
              Label(
                String(localized: "Each server address must be unique."), systemImage: "exclamationmark.triangle.fill"
              )
              .foregroundStyle(.orange)
            }
            Text(
              String(
                localized:
                  "Add multiple addresses for the same server (e.g. public URL, LAN, or Tailscale). The selected address is used first; if it becomes unreachable, KMReader automatically tries the others in order."
              )
            )
          }
          .font(.caption)
        ) {
          ForEach($endpoints) { $endpoint in
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 8) {
                Button {
                  selectActiveEndpoint(endpoint.id)
                } label: {
                  HStack(spacing: 6) {
                    Image(
                      systemName: endpoint.id == activeEndpointID
                        ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(
                      endpoint.id == activeEndpointID ? Color.serverGreen : Color.secondary
                    )
                    Text(String(localized: "Active"))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  .contentShape(Rectangle())
                }
                .adaptiveButtonStyle(.borderless)

                Spacer()

                ServerEndpointStatusLabel(
                  status: ServerEndpointHealthStore.shared.status(for: endpoint.id)
                )
              }

              TextField(String(localized: "Label (optional)"), text: $endpoint.name)
                #if os(iOS) || os(tvOS)
                  .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

              TextField(String(localized: "Server URL"), text: $endpoint.url)
                .textContentType(.URL)
                #if os(iOS) || os(tvOS)
                  .textInputAutocapitalization(.never)
                  .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                .onChange(of: endpoint.url) { _, _ in
                  ServerEndpointHealthStore.shared.clear(endpointID: endpoint.id)
                  if endpoint.id == activeEndpointID {
                    resetValidation()
                  }
                }
            }
            .padding(.vertical, 4)
            .contextMenu {
              if endpoint.id != activeEndpointID {
                Button {
                  selectActiveEndpoint(endpoint.id)
                } label: {
                  Label(String(localized: "Set Active"), systemImage: "checkmark.circle")
                }
              }
              if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
                if index > 0 {
                  Button {
                    moveEndpoint(from: index, to: index - 1)
                  } label: {
                    Label(String(localized: "Move Up"), systemImage: "arrow.up")
                  }
                }
                if index < endpoints.count - 1 {
                  Button {
                    moveEndpoint(from: index, to: index + 1)
                  } label: {
                    Label(String(localized: "Move Down"), systemImage: "arrow.down")
                  }
                }
              }
              if endpoints.count > 1 {
                Divider()
                Button(role: .destructive) {
                  if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
                    deleteEndpoints(at: IndexSet(integer: index))
                  }
                } label: {
                  Label(String(localized: "Remove Address"), systemImage: "trash")
                }
              }
            }
          }
          .onMove(perform: moveEndpoints)
          .onDelete(perform: deleteEndpoints)

          Button {
            addEndpoint()
          } label: {
            Label(String(localized: "Add Address"), systemImage: "plus.circle")
          }
          .adaptiveButtonStyle(.borderless)
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

        Section(
          header: Text(String(localized: "Privacy")),
          footer: Group {
            if !LocalDeviceAuthenticationService.shared.canAuthenticate && !protected {
              Text(
                String(
                  localized:
                    "Protected servers require device authentication, which is not available on this device."
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        ) {
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
          Label(String(localized: "Save"), systemImage: AppIcon.confirm)
        }
      }
      .disabled(!canSave)
    }
    .task {
      ServerEndpointHealthStore.shared.probe(
        endpoints: endpoints,
        authToken: instance.authToken,
        authMethod: instance.authMethod
      )
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

  private var normalizedEndpoints: [ServerEndpoint] {
    ServerEndpoint.normalized(endpoints)
  }

  private var activeEndpoint: ServerEndpoint? {
    if let selected = normalizedEndpoints.first(where: { $0.id == activeEndpointID }) {
      return selected
    }
    return normalizedEndpoints.first
  }

  private var trimmedServerURL: String {
    activeEndpoint?.normalizedURL ?? ""
  }

  private var trimmedUsername: String {
    username.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var hasIncompleteEndpoint: Bool {
    endpoints.contains { $0.normalizedURL.isEmpty }
  }

  private var hasDuplicateEndpoints: Bool {
    let urls = endpoints.map(\.normalizedURL).filter { !$0.isEmpty }
    return Set(urls).count != urls.count
  }

  private var hasChanges: Bool {
    if trimmedName != instance.name || trimmedServerURL != instance.serverURL
      || normalizedEndpoints != ServerEndpoint.normalized(instance.endpoints)
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

  private var credentialsChanged: Bool {
    if authMethod != instance.authMethod {
      return true
    }
    if authMethod == .basicAuth {
      return trimmedUsername != instance.username || !password.isEmpty
    } else {
      return apiKey != instance.authToken
    }
  }

  private var activeURLChanged: Bool {
    trimmedServerURL != Current.normalizeServerURL(instance.serverURL)
  }

  private var canSave: Bool {
    guard !isSaving, !isValidating else { return false }
    guard !trimmedServerURL.isEmpty, !hasIncompleteEndpoint, !hasDuplicateEndpoints else { return false }

    if authMethod == .basicAuth {
      guard !trimmedUsername.isEmpty else { return false }
    } else {
      guard !apiKey.isEmpty else { return false }
    }

    guard hasChanges else { return false }

    // Unreachable backup addresses can still be saved (e.g. adding a LAN
    // address while away from home); new credentials or a new active URL must
    // validate first.
    if credentialsChanged || activeURLChanged {
      return isValidated
    }
    return true
  }

  private var canValidate: Bool {
    guard !isValidating, !trimmedServerURL.isEmpty else { return false }

    if authMethod == .basicAuth {
      guard !trimmedUsername.isEmpty else { return false }
      if !password.isEmpty { return true }
      return trimmedUsername == instance.username && instance.authMethod == .basicAuth
    } else {
      return !apiKey.isEmpty
    }
  }

  private func selectActiveEndpoint(_ id: UUID) {
    guard activeEndpointID != id else { return }
    activeEndpointID = id
    resetValidation()
  }

  private func addEndpoint() {
    withAnimation {
      let endpoint = ServerEndpoint(url: "")
      endpoints.append(endpoint)
      if activeEndpoint == nil {
        activeEndpointID = endpoint.id
      }
    }
  }

  private func moveEndpoints(from source: IndexSet, to destination: Int) {
    endpoints.move(fromOffsets: source, toOffset: destination)
  }

  private func moveEndpoint(from index: Int, to target: Int) {
    guard endpoints.indices.contains(index), endpoints.indices.contains(target) else { return }
    withAnimation {
      let item = endpoints.remove(at: index)
      endpoints.insert(item, at: target)
    }
  }

  private func deleteEndpoints(at offsets: IndexSet) {
    guard endpoints.count > 1 else { return }
    let removedIDs = offsets.map { endpoints[$0].id }
    withAnimation {
      endpoints.remove(atOffsets: offsets)
      if removedIDs.contains(activeEndpointID), let first = endpoints.first {
        activeEndpointID = first.id
        resetValidation()
      }
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
            endpoints: normalizedEndpoints,
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
            let switched = await authViewModel.switchEndpoint(
              updatedInstance.activeEndpoint, of: updatedInstance)
            if !switched {
              // Persist the newly saved active route locally even when it is
              // unreachable right now (e.g. configuring a LAN address remotely).
              var updated = AppConfig.current
              updated.serverURL = updatedInstance.serverURL
              updated.serverDisplayName = updatedInstance.displayName
              updated.authToken = updatedInstance.authToken
              updated.authMethod = updatedInstance.authMethod
              updated.username = updatedInstance.username
              updated.sessionToken = ""
              AppConfig.current = updated
            }
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

    let endpointsToProbe = normalizedEndpoints
    let activeURL = trimmedServerURL
    Task {
      ServerEndpointHealthStore.shared.probe(
        endpoints: endpointsToProbe,
        authToken: tokenToTest,
        authMethod: authMethod,
        force: true
      )
      do {
        let user = try await authViewModel.testCredentials(
          serverURL: activeURL,
          authToken: tokenToTest,
          authMethod: authMethod
        )

        withAnimation {
          validationMessage = String(localized: "Connection validated successfully")
          isValidated = true
          isValidating = false

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
