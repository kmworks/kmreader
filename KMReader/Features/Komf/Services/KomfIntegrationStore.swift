//
// KomfIntegrationStore.swift
//
//

import Foundation

/// Whether the komf menus show for the current instance: the endpoints are
/// admin-only, and the server profile lists `komf` only while the integration
/// is connected.
@MainActor
@Observable
final class KomfIntegrationStore {
  static let shared = KomfIntegrationStore()

  private(set) var isAvailable = false

  private init() {}

  func refresh(isAdmin: Bool) async {
    let instanceId = AppConfig.current.instanceId
    isAvailable =
      isAdmin && !AppConfig.isOffline && !instanceId.isEmpty
      && ServerProfileService.supports(.komf, instanceId: instanceId)
  }

  /// A 409 means the integration dropped server-side: re-read the profile.
  func handleConflictIfNeeded(_ error: Error) async {
    guard case APIError.httpError(let code, _, _, _, _) = error, code == 409 else { return }
    await ServerProfileService.refresh(instanceId: AppConfig.current.instanceId)
    await refresh(isAdmin: AppConfig.current.isAdmin)
  }
}
