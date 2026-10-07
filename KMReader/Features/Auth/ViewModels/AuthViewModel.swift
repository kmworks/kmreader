//
// AuthViewModel.swift
//
//

import Foundation
import SwiftUI

@MainActor
@Observable
class AuthViewModel {
  private let logger = AppLogger(.auth)

  enum BootstrapState: Equatable {
    case requiresValidation
    case validating
    case ready
  }

  var isLoading = false
  var isSwitching = false
  var switchingInstanceId: String?
  private(set) var bootstrapState: BootstrapState

  init() {
    bootstrapState = AppConfig.isLoggedIn ? .requiresValidation : .ready
  }

  func login(
    username: String,
    password: String,
    serverURL: String,
    displayName: String? = nil,
    autoCreateApiKey: Bool
  ) async throws {
    isLoading = true
    defer { isLoading = false }

    // Validate authentication using temporary request
    let result = try await AuthService.login(
      username: username, password: password, serverURL: serverURL, timeout: AppConfig.authTimeout)

    // When enabled, prefer an auto-created API key over storing the password
    // credential: it never expires and works for background downloads without
    // relying on shared cookies. Falls back to password auth when the server
    // cannot create keys.
    var authToken = result.authToken
    var authMethod = AuthenticationMethod.basicAuth
    var apiKeyId: String?
    if autoCreateApiKey, let apiKey = await createApiKeyCredential(serverURL: serverURL) {
      authToken = apiKey.key
      authMethod = .apiKey
      apiKeyId = apiKey.id
    }

    // Apply login configuration
    try await applyLoginConfiguration(
      serverURL: serverURL,
      username: username,
      authToken: authToken,
      authMethod: authMethod,
      apiKeyId: apiKeyId,
      user: result.user,
      displayName: displayName,
      shouldPersistInstance: true,
      successMessage: String(localized: "Logged in successfully")
    )
  }

  /// Create and verify an API key while a password-based session is still
  /// valid. Returns nil (and keeps the caller on password auth) when key
  /// creation or verification fails, e.g. on older servers.
  private func createApiKeyCredential(serverURL: String) async -> ApiKey? {
    do {
      let comment = ApiKey.appManagedComment(deviceName: PlatformHelper.deviceName)
      let apiKey = try await AuthService.createApiKey(comment: comment)
      // Replace the password-established session with an API-key-established
      // one; this also verifies the key authenticates. Requests carrying
      // both X-Auth-Token and X-API-Key only skip server-side API key
      // re-authentication when the session itself holds an
      // ApiKeyAuthenticationToken; riding the password session would
      // re-authenticate every request and flood the authentication activity
      // log.
      _ = try await AuthService.establishSession(
        serverURL: serverURL,
        authToken: apiKey.key,
        authMethod: .apiKey
      )
      logger.info("🔑 Created API key credential for \(serverURL)")
      await AuthService.deleteStaleAppManagedKeys(
        serverURL: serverURL, authToken: apiKey.key, comment: comment, keeping: apiKey.id)
      return apiKey
    } catch {
      logger.warning(
        "⚠️ API key creation failed, keeping password authentication for \(serverURL): \(error.diagnosticDescription)"
      )
      return nil
    }
  }

  func loginWithAPIKey(
    apiKey: String,
    serverURL: String,
    displayName: String? = nil
  ) async throws {
    isLoading = true
    defer { isLoading = false }

    // Validate authentication using API Key
    let result = try await AuthService.loginWithAPIKey(
      apiKey: apiKey, serverURL: serverURL, timeout: AppConfig.authTimeout)

    // Apply login configuration
    try await applyLoginConfiguration(
      serverURL: serverURL,
      username: result.user.email,
      authToken: result.apiKey,
      authMethod: .apiKey,
      user: result.user,
      displayName: displayName,
      shouldPersistInstance: true,
      successMessage: String(localized: "Logged in successfully")
    )
  }

  func logout(clearCurrent: Bool = false) {
    LocalDeviceAuthenticationService.shared.clearProtectedAccess()
    let instanceId = AppConfig.current.instanceId
    let libraryIds = AppConfig.dashboard.libraryIds
    Task {
      await DashboardLibrarySelectionStore.persistSelection(libraryIds, instanceId: instanceId)
      // Disconnect SSE before logout
      await SSEService.shared.disconnect()
      try? await AuthService.logout(clearCurrent: clearCurrent)
    }
    // ViewModel-specific cleanup
    AppConfig.isLoggedIn = false
    AppConfig.showProtectedServers = false
    if clearCurrent {
      AppConfig.current = Current()
    } else {
      var current = AppConfig.current
      current.clearUserMetadata()
      AppConfig.current = current
    }
    bootstrapState = .requiresValidation
  }

  func validate(serverURL: String) async throws {
    try await AuthService.validate(serverURL: serverURL)
  }

  func testCredentials(
    serverURL: String, authToken: String, authMethod: AuthenticationMethod = .basicAuth
  ) async throws -> User {
    return try await AuthService.testCredentials(
      serverURL: serverURL, authToken: authToken, authMethod: authMethod)
  }

  /// Load current user from server.
  /// Returns true if server is reachable, false if offline/unreachable.
  /// 401 errors trigger logout.
  func loadCurrentUser(timeout: TimeInterval? = nil) async -> Bool {
    isLoading = true
    bootstrapState = .validating
    defer { isLoading = false }
    do {
      let effectiveTimeout = timeout ?? AppConfig.authTimeout
      let user = try await AuthService.getCurrentUser(timeout: effectiveTimeout)
      var current = AppConfig.current
      current.updateMetadata(from: user)
      AppConfig.current = current
      bootstrapState = .ready
      return true
    } catch {
      if let apiError = error as? APIError {
        switch apiError {
        case .unauthorized:
          // 401: logout
          logout()
          return true  // Server is reachable, just not authorized
        case .networkError:
          // Server unreachable
          bootstrapState = .ready
          return false
        default:
          // Other API errors - server is reachable
          bootstrapState = .ready
          ErrorManager.shared.alert(error: error)
          return true
        }
      }
      // Non-API errors (likely network issues)
      bootstrapState = .ready
      return false
    }
  }

  /// User explicitly opted into offline mode: drop pending dashboard
  /// auto-refreshes, persist the manual flag (no automatic recovery), and
  /// disconnect SSE. Reconnecting stays an explicit user action.
  func enterOfflineMode() {
    DashboardRefreshCoordinator.shared.cancelPendingAutoRefresh(clearDeferred: true)
    AppConfig.enterManualOfflineMode()
    Task {
      await SSEService.shared.disconnect(notify: false)
    }
  }

  /// Manual exit from offline mode: probe the server first, and stay offline
  /// when it does not answer — a failed retry keeps the current offline
  /// classification (manual or auto) instead of reclassifying. On success
  /// flip back online, reconnect SSE, and reload dashboard sections.
  func reconnect() async -> Bool {
    let serverReachable = await loadCurrentUser()
    let reconnected = serverReachable && AppConfig.isLoggedIn
    guard reconnected else { return false }
    AppConfig.exitOfflineMode()
    await SSEService.shared.connect()
    ErrorManager.shared.notify(message: String(localized: "settings.connection_restored"))
    await DashboardSectionRefreshNotifier.postAll(source: .manual, reason: "Reconnected")
    return true
  }

  func switchTo(instance: ServerDisplayItem) async -> Bool {
    if instance.protected {
      let authenticated = await LocalDeviceAuthenticationService.shared.authenticateProtectedAccess(
        reason: String(localized: "Authenticate to switch to this protected server.")
      )
      guard authenticated else { return false }
    }

    isSwitching = true
    switchingInstanceId = instance.instanceId
    defer {
      isSwitching = false
      switchingInstanceId = nil
    }

    // Ensure current session is logged out before switching to a new instance when sharing a single session
    await DashboardLibrarySelectionStore.persistCurrentSelection()
    try? await AuthService.logout()

    // Establish stateful session before switching
    do {
      let validatedUser = try await AuthService.establishSession(
        serverURL: instance.serverURL,
        authToken: instance.authToken,
        authMethod: instance.authMethod,
        timeout: AppConfig.authTimeout
      )

      // Apply switch configuration
      try await applyLoginConfiguration(
        serverURL: instance.serverURL,
        username: instance.username,
        authToken: instance.authToken,
        authMethod: instance.authMethod,
        user: validatedUser,
        displayName: instance.displayName,
        instanceId: instance.instanceId,
        shouldPersistInstance: false,
        protected: instance.protected,
        successMessage: String(localized: "Switched to \(instance.name)")
      )

      return true
    } catch let apiError as APIError {
      // Check if this is a network error - switch to offline mode
      if case .networkError = apiError {
        // Set up the instance config without full login
        APIClient.shared.setServer(url: instance.serverURL)
        APIClient.shared.setAuthToken(instance.authToken)

        AppConfig.current = Current(
          serverURL: instance.serverURL,
          serverDisplayName: instance.displayName,
          authToken: instance.authToken,
          authMethod: instance.authMethod,
          username: instance.username,
          isAdmin: false,
          instanceId: instance.instanceId
        )

        AppConfig.isLoggedIn = true

        await DashboardLibrarySelectionStore.loadSelection(for: instance.instanceId)

        // Switch to offline mode
        AppConfig.enterAutoOfflineMode()
        await SSEService.shared.disconnect()

        // We cannot load the user object offline, but isLoggedIn=true allows entry
        var current = AppConfig.current
        current.clearUserMetadata()
        AppConfig.current = current
        bootstrapState = .ready
        if instance.protected {
          ExternalContentSurfaceService.clearAll()
        }

        ErrorManager.shared.notify(
          message: String(localized: "Server unreachable, switched to offline mode")
        )
        return true
      }

      // Non-network errors: show alert and fail
      ErrorManager.shared.alert(error: apiError)
      return false
    } catch {
      ErrorManager.shared.alert(error: error)
      return false
    }
  }

  private func applyLoginConfiguration(
    serverURL: String,
    username: String,
    authToken: String,
    authMethod: AuthenticationMethod,
    apiKeyId: String? = nil,
    user: User,
    displayName: String?,
    instanceId: String? = nil,
    shouldPersistInstance: Bool,
    protected: Bool = false,
    successMessage: String
  ) async throws {
    // Normalize before persisting anywhere (AppConfig AND the instance
    // row). Login validation succeeds even with a trailing slash because
    // `buildLoginRequest` normalizes its URL seam locally — without this,
    // the raw slashed URL would be persisted and every subsequent
    // naively-concatenated request URL (`serverURL + "/api/..."`) would
    // 400 against Komga's strict path firewall.
    let serverURL = Current.normalizeServerURL(serverURL)

    // Update AppConfig only after validation succeeds
    APIClient.shared.setServer(url: serverURL)
    APIClient.shared.setAuthToken(authToken)
    await DashboardLibrarySelectionStore.persistCurrentSelection()

    let finalInstanceId: String
    let finalDisplayName: String
    let finalProtected: Bool

    // Persist instance if this is a new login
    if shouldPersistInstance {
      let instanceSummary = try await DatabaseOperator.database().upsertInstance(
        serverURL: serverURL,
        username: username,
        authToken: authToken,
        isAdmin: user.isAdmin,
        authMethod: authMethod,
        apiKeyId: apiKeyId,
        displayName: displayName
      )
      finalInstanceId = instanceSummary.id.uuidString
      finalDisplayName = instanceSummary.displayName
      finalProtected = instanceSummary.protected
    } else {
      finalInstanceId = instanceId ?? AppConfig.current.instanceId
      finalDisplayName = displayName ?? ""
      finalProtected = protected
    }

    // Carry the session token established during login/switch into the new
    // Current instead of dropping it. Without it every request would go out
    // session-less, forcing full server-side re-authentication (one
    // authentication activity row per request for API key requests).
    let sessionToken = AppConfig.current.sessionToken

    AppConfig.current = Current(
      serverURL: serverURL,
      serverDisplayName: finalDisplayName,
      authToken: authToken,
      authMethod: authMethod,
      username: user.email,
      isAdmin: user.isAdmin,
      instanceId: finalInstanceId,
      sessionToken: sessionToken
    )

    AppConfig.isLoggedIn = true

    // Reset offline mode on successful login/switch
    if AppConfig.isOffline {
      AppConfig.exitOfflineMode()
    }

    await DashboardLibrarySelectionStore.loadSelection(for: finalInstanceId)

    // Load libraries
    await LibraryManager.shared.loadLibraries()

    // Update user and credentials version
    var current = AppConfig.current
    current.updateMetadata(from: user)
    AppConfig.current = current

    // Show success message
    ErrorManager.shared.notify(message: successMessage)
    bootstrapState = .ready

    // Reconnect SSE with new instance if enabled
    await SSEService.shared.disconnect()
    await SSEService.shared.connect()

    ExternalContentSurfaceService.updateAfterSelectingInstance(
      instanceId: finalInstanceId,
      protected: finalProtected
    )
  }

  func updatePassword(password: String) async throws {
    let userId = AppConfig.current.userId
    guard !userId.isEmpty else { return }
    try await AuthService.updatePassword(userId: userId, password: password)
  }
}
