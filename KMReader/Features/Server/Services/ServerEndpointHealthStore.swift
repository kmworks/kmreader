//
// ServerEndpointHealthStore.swift
//

import Foundation

@MainActor
@Observable
final class ServerEndpointHealthStore {
  static let shared = ServerEndpointHealthStore()

  private(set) var statuses: [UUID: ServerEndpointProbeStatus] = [:]
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var lastProbedAt: [UUID: Date] = [:]
  private let minimumRefreshInterval: TimeInterval = 10

  private init() {}

  func status(for endpointID: UUID) -> ServerEndpointProbeStatus? {
    statuses[endpointID]
  }

  func probe(instances: [ServerDisplayItem], force: Bool = false) {
    let current = AppConfig.current
    let currentURL = Current.normalizeServerURL(current.serverURL)
    for instance in instances {
      for endpoint in instance.endpoints {
        let isActiveAPIKeyRoute =
          instance.instanceId == current.instanceId
          && endpoint.normalizedURL == currentURL && instance.authMethod == .apiKey
        probe(
          endpoint: endpoint,
          authToken: instance.authToken,
          authMethod: instance.authMethod,
          sessionToken: isActiveAPIKeyRoute ? current.sessionToken : nil,
          force: force
        )
      }
    }
  }

  func probe(
    endpoints: [ServerEndpoint],
    authToken: String,
    authMethod: AuthenticationMethod,
    force: Bool = false
  ) {
    for endpoint in endpoints {
      probe(endpoint: endpoint, authToken: authToken, authMethod: authMethod, force: force)
    }
  }

  func probe(
    endpoint: ServerEndpoint,
    authToken: String,
    authMethod: AuthenticationMethod,
    sessionToken: String? = nil,
    force: Bool = false
  ) {
    let normalizedURL = endpoint.normalizedURL
    guard !normalizedURL.isEmpty else { return }
    guard tasks[endpoint.id] == nil else { return }
    if !force, let last = lastProbedAt[endpoint.id],
      Date().timeIntervalSince(last) < minimumRefreshInterval
    {
      return
    }

    statuses[endpoint.id] = .checking
    lastProbedAt[endpoint.id] = Date()
    let endpointID = endpoint.id
    let probeTarget = ServerEndpoint(id: endpoint.id, name: endpoint.name, url: normalizedURL)
    tasks[endpointID] = Task { [weak self] in
      let result = await ServerEndpointProbeService.probe(
        endpoint: probeTarget,
        authToken: authToken,
        authMethod: authMethod,
        sessionToken: sessionToken
      )
      guard let self, !Task.isCancelled else { return }
      self.tasks[endpointID] = nil
      self.statuses[endpointID] = result
    }
  }

  func clear(endpointID: UUID) {
    tasks[endpointID]?.cancel()
    tasks[endpointID] = nil
    statuses[endpointID] = nil
    lastProbedAt[endpointID] = nil
  }
}
