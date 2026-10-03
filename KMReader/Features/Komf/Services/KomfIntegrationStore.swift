//
// KomfIntegrationStore.swift
//
//

import Foundation

/// Caches the current instance's komf integration status for detail-page menus.
/// The endpoints are kmrs-private and admin-only; Komga servers 404, which is
/// recorded per instance for 24h so the probe is not repeated on every page.
@MainActor
@Observable
final class KomfIntegrationStore {
  static let shared = KomfIntegrationStore()

  private static let unsupportedTTL: TimeInterval = 24 * 60 * 60

  private(set) var integration: KomfIntegration?
  private var checkedInstanceId: String?

  var isAvailable: Bool {
    integration?.isConnected == true
  }

  private init() {}

  func refresh(isAdmin: Bool) async {
    let instanceId = AppConfig.current.instanceId
    guard isAdmin, !AppConfig.isOffline, !instanceId.isEmpty else {
      integration = nil
      checkedInstanceId = nil
      return
    }
    guard checkedInstanceId != instanceId else { return }

    if let record = AppConfig.serverKomfCapability.record(instanceId: instanceId),
      !record.supported,
      Date().timeIntervalSince(record.checkedAt) < Self.unsupportedTTL
    {
      integration = nil
      checkedInstanceId = instanceId
      return
    }

    do {
      let fetched = try await KomfService.getIntegration()
      integration = fetched
      checkedInstanceId = instanceId
      var capability = AppConfig.serverKomfCapability
      capability.upsert(instanceId: instanceId, supported: true, checkedAt: Date())
      AppConfig.serverKomfCapability = capability
    } catch {
      integration = nil
      checkedInstanceId = instanceId
      if case APIError.notFound = error {
        var capability = AppConfig.serverKomfCapability
        capability.upsert(instanceId: instanceId, supported: false, checkedAt: Date())
        AppConfig.serverKomfCapability = capability
      }
    }
  }

  /// Re-probe after an action failed with a conflict (integration dropped server-side).
  func invalidate() {
    checkedInstanceId = nil
    integration = nil
  }
}
