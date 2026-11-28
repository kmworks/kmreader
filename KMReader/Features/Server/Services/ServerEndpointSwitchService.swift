//
// ServerEndpointSwitchService.swift
//

import Foundation

/// Switches the active network route of a Komga instance without tearing down
/// instance-scoped state (libraries, local projections, reader session), and
/// fails over to an alternate endpoint before the app enters offline mode.
@MainActor
@Observable
final class ServerEndpointSwitchService {
  static let shared = ServerEndpointSwitchService()

  enum SwitchReason: Equatable {
    case manual
    case failover
  }

  private struct FailoverOutcome {
    let failedURL: String
    let succeeded: Bool
    let completedAt: Date
  }

  private let logger = AppLogger(.auth)
  private(set) var switchingEndpointID: UUID?
  private var failoverTask: Task<Bool, Never>?
  private var lastOutcome: FailoverOutcome?
  private var instanceSwitchCount = 0

  /// True while an endpoint switch, instance switch, or failover probe owns
  /// connection state. `APIClient` checks this so switch/probe requests do
  /// not trip the offline failure tracker or start a nested failover.
  var isHandlingConnectionChange: Bool {
    switchingEndpointID != nil || failoverTask != nil || instanceSwitchCount > 0
  }

  private init() {}

  func beginInstanceSwitch() {
    lastOutcome = nil
    instanceSwitchCount += 1
  }

  func endInstanceSwitch() {
    instanceSwitchCount = max(0, instanceSwitchCount - 1)
  }

  func switchEndpoint(
    _ endpoint: ServerEndpoint,
    for instance: ServerDisplayItem,
    reason: SwitchReason = .manual
  ) async -> Bool {
    let targetURL = endpoint.normalizedURL
    guard !targetURL.isEmpty else { return false }

    let previous = AppConfig.current
    guard !previous.instanceId.isEmpty, previous.instanceId == instance.instanceId else {
      logger.warning("⚠️ Ignored endpoint switch for non-active instance \(instance.instanceId)")
      return false
    }

    if reason == .manual {
      lastOutcome = nil
    }

    if Current.normalizeServerURL(previous.serverURL) == targetURL,
      previous.authToken == instance.authToken, previous.authMethod == instance.authMethod,
      !AppConfig.isOffline, reason == .manual
    {
      if previous.serverDisplayName != instance.displayName {
        var updated = previous
        updated.serverDisplayName = instance.displayName
        AppConfig.current = updated
      }
      return true
    }

    switchingEndpointID = endpoint.id
    defer { switchingEndpointID = nil }

    do {
      // Session tokens are host-specific; establish a fresh session on the
      // target endpoint so API-key requests don't re-authenticate per request.
      let user = try await AuthService.establishSession(
        serverURL: targetURL,
        authToken: instance.authToken,
        authMethod: instance.authMethod,
        timeout: AppConfig.authTimeout
      )

      guard AppConfig.isLoggedIn, AppConfig.current.instanceId == instance.instanceId else {
        AppConfig.current = previous
        return false
      }
      var updated = AppConfig.current
      updated.serverURL = targetURL
      updated.authToken = instance.authToken
      updated.authMethod = instance.authMethod
      updated.serverDisplayName = instance.displayName
      updated.updateMetadata(from: user)
      AppConfig.current = updated

      if AppConfig.isOffline {
        AppConfig.exitOfflineMode()
      }

      if let database = await DatabaseOperator.databaseIfConfigured() {
        try? await database.updateInstanceActiveEndpoint(
          instanceId: instance.instanceId, serverURL: targetURL)
      }

      ServerEndpointHealthStore.shared.probe(
        endpoint: endpoint,
        authToken: instance.authToken,
        authMethod: instance.authMethod,
        sessionToken: instance.authMethod == .apiKey ? updated.sessionToken : nil,
        force: true
      )

      await SSEService.shared.disconnect(notify: false)
      await SSEService.shared.connect()

      switch reason {
      case .manual:
        ErrorManager.shared.notify(
          message: String(localized: "Switched to \(endpoint.displayName)"))
      case .failover:
        ErrorManager.shared.notify(
          message: String(localized: "Connected via \(endpoint.displayName)"))
      }

      logger.info("🔀 Switched instance \(instance.instanceId) to endpoint \(targetURL)")
      await DashboardSectionRefreshNotifier.postAll(source: .auto, reason: "Endpoint switched")
      return true
    } catch {
      AppConfig.current = previous
      if reason == .manual {
        if let apiError = error as? APIError, case .networkError = apiError {
          ErrorManager.shared.notify(message: String(localized: "Server unreachable"))
        } else {
          ErrorManager.shared.alert(error: error)
        }
      } else {
        logger.warning(
          "⚠️ Failover to \(targetURL) failed: \(error.diagnosticDescription)")
      }
      return false
    }
  }

  /// Probe alternate endpoints of the current instance in priority order and
  /// switch to the first reachable one. Coalesces concurrent callers and
  /// deduplicates an immediate follow-up for the same failed URL (e.g. when
  /// `APIClient.handleNetworkError` and `AuthViewModel.loadCurrentUser` both
  /// observe the same failed request).
  func attemptFailover() async -> Bool {
    if let failoverTask {
      return await failoverTask.value
    }
    guard AppConfig.isLoggedIn, !AppConfig.current.instanceId.isEmpty else { return false }

    let instanceId = AppConfig.current.instanceId
    let currentURL = Current.normalizeServerURL(AppConfig.current.serverURL)
    if let lastOutcome, lastOutcome.failedURL == currentURL,
      Date().timeIntervalSince(lastOutcome.completedAt) < 5
    {
      return lastOutcome.succeeded
    }

    let task = Task<Bool, Never> { [weak self] in
      guard let self else { return false }
      let succeeded = await self.performFailover(instanceId: instanceId, excluding: currentURL)
      // Only failed outcomes are replayed (to keep `loadCurrentUser` from
      // re-probing right after `APIClient` already tried every endpoint). A
      // success changes the active URL, and callers detect that directly.
      self.lastOutcome =
        succeeded
        ? nil
        : FailoverOutcome(failedURL: currentURL, succeeded: false, completedAt: Date())
      self.failoverTask = nil
      return succeeded
    }
    failoverTask = task
    return await task.value
  }

  private func performFailover(instanceId: String, excluding currentURL: String) async -> Bool {
    guard let database = await DatabaseOperator.databaseIfConfigured(),
      let instance = try? await database.fetchServerDisplayItem(instanceId: instanceId),
      instance.hasMultipleEndpoints
    else {
      return false
    }

    let candidates = await Self.reachableAlternates(for: instance, excluding: currentURL)
    for candidate in candidates {
      guard AppConfig.isLoggedIn, AppConfig.current.instanceId == instanceId else { return false }
      if await switchEndpoint(candidate, for: instance, reason: .failover) {
        return true
      }
    }
    return false
  }

  /// Probe all endpoints except `excluding` concurrently and return the first
  /// reachable one in the instance's priority order.
  static func firstReachableAlternate(
    for instance: ServerDisplayItem,
    excluding excludedURL: String
  ) async -> ServerEndpoint? {
    await reachableAlternates(for: instance, excluding: excludedURL).first
  }

  /// Probe all endpoints except `excluding` concurrently and return every
  /// reachable endpoint in the instance's priority order.
  static func reachableAlternates(
    for instance: ServerDisplayItem,
    excluding excludedURL: String
  ) async -> [ServerEndpoint] {
    let normalizedExcluded = Current.normalizeServerURL(excludedURL)
    let candidates = instance.endpoints.filter {
      !$0.normalizedURL.isEmpty && $0.normalizedURL != normalizedExcluded
    }
    guard !candidates.isEmpty else { return [] }

    return await withTaskGroup(of: (UUID, Bool).self, returning: [ServerEndpoint].self) { group in
      for endpoint in candidates {
        group.addTask {
          let status = await ServerEndpointProbeService.probe(
            endpoint: endpoint,
            authToken: instance.authToken,
            authMethod: instance.authMethod,
            timeout: 4.0
          )
          if case .reachable = status {
            return (endpoint.id, true)
          }
          return (endpoint.id, false)
        }
      }

      var results: [UUID: Bool] = [:]
      var settledPrefixCount = 0
      var resolved: [ServerEndpoint] = []
      for await (id, reachable) in group {
        results[id] = reachable
        while settledPrefixCount < candidates.count,
          let prefixReachable = results[candidates[settledPrefixCount].id]
        {
          if prefixReachable {
            resolved.append(candidates[settledPrefixCount])
          }
          settledPrefixCount += 1
        }
        // Once a reachable endpoint has no higher-priority probes still
        // pending, lower-priority probes cannot change the pick.
        if !resolved.isEmpty {
          group.cancelAll()
          return resolved
        }
      }
      return []
    }
  }
}
