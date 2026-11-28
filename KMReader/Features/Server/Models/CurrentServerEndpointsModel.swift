//
// CurrentServerEndpointsModel.swift
//

import Foundation

@MainActor
@Observable
final class CurrentServerEndpointsModel {
  private(set) var instance: ServerDisplayItem?

  var activeEndpoint: ServerEndpoint? {
    guard let instance else { return nil }
    let currentURL = Current.normalizeServerURL(AppConfig.current.serverURL)
    return instance.endpoints.first(where: { $0.normalizedURL == currentURL })
      ?? instance.activeEndpoint
  }

  var hasMultipleEndpoints: Bool {
    instance?.hasMultipleEndpoints ?? false
  }

  func refresh(forceProbe: Bool = false) async {
    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty, let database = await DatabaseOperator.databaseIfConfigured() else {
      instance = nil
      return
    }
    let loaded = try? await database.fetchServerDisplayItem(instanceId: instanceId)
    guard AppConfig.current.instanceId == instanceId else { return }
    instance = loaded
    if let loaded {
      ServerEndpointHealthStore.shared.probe(instances: [loaded], force: forceProbe)
    }
  }

  func probe() {
    guard let instance else { return }
    ServerEndpointHealthStore.shared.probe(instances: [instance], force: true)
  }

  func status(for endpoint: ServerEndpoint) -> ServerEndpointProbeStatus? {
    ServerEndpointHealthStore.shared.status(for: endpoint.id)
  }

  func isActive(_ endpoint: ServerEndpoint) -> Bool {
    endpoint.normalizedURL == Current.normalizeServerURL(AppConfig.current.serverURL)
  }

  func switchEndpoint(_ endpoint: ServerEndpoint, using authViewModel: AuthViewModel) {
    guard let instance, !isActive(endpoint) else { return }
    Task {
      let switched = await authViewModel.switchEndpoint(endpoint, of: instance)
      if switched {
        await refresh()
      }
    }
  }
}
