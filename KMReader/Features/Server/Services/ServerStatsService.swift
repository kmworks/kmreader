//
// ServerStatsService.swift
//
//

import Foundation

/// The kmrs-private stats endpoints (`/api/v1/stats/libraries`,
/// `/api/v1/stats/server`). Komga and older kmrs servers 404; the first
/// failure is recorded per instance so later loads skip the doomed request.
nonisolated enum ServerStatsService {
  private static let apiClient = APIClient.shared

  // An unsupported verdict expires after this interval so a server upgrade is picked up.
  private static let capabilityRecheckInterval: TimeInterval = 24 * 60 * 60

  static func shouldQueryServer(instanceId: String) -> Bool {
    guard !AppConfig.isOffline else { return false }
    guard let record = AppConfig.serverStatsCapability.record(instanceId: instanceId) else {
      return true
    }
    if record.supported { return true }
    return Date().timeIntervalSince(record.checkedAt) >= capabilityRecheckInterval
  }

  static func recordServerCapability(instanceId: String, supported: Bool) {
    var capability = AppConfig.serverStatsCapability
    // A repeated supported verdict is not worth a UserDefaults round-trip; an
    // unsupported verdict must always refresh checkedAt, it throttles re-probes.
    guard !(supported && capability.record(instanceId: instanceId)?.supported == true) else { return }
    capability.upsert(instanceId: instanceId, supported: supported, checkedAt: Date())
    AppConfig.serverStatsCapability = capability
  }

  static func getLibrariesStats() async throws -> ServerLibrariesStatsResponse {
    try await apiClient.request(path: "/api/v1/stats/libraries")
  }

  static func getServerStats() async throws -> ServerStatsResponse {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    return try await apiClient.request(path: "/api/v1/stats/server")
  }

  /// `getServerStats` behind the capability probe: nil means the server has
  /// no stats endpoints (verdict recorded) and the caller should fall back to
  /// the actuator metrics; other failures propagate.
  static func getServerStatsIfSupported(instanceId: String) async throws -> ServerStatsResponse? {
    guard shouldQueryServer(instanceId: instanceId) else { return nil }
    do {
      let stats = try await getServerStats()
      recordServerCapability(instanceId: instanceId, supported: true)
      return stats
    } catch let error as APIError {
      guard case .notFound = error else { throw error }
      recordServerCapability(instanceId: instanceId, supported: false)
      return nil
    }
  }
}
