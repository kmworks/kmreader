//
// ServerStatsService.swift
//
//

import Foundation

/// The kmrs-private stats endpoints (`/api/v1/stats/libraries`,
/// `/api/v1/stats/server`), present where the server profile lists `serverStats`.
nonisolated enum ServerStatsService {
  private static let apiClient = APIClient.shared

  static func isSupported(instanceId: String) -> Bool {
    !AppConfig.isOffline && ServerProfileService.supports(.serverStats, instanceId: instanceId)
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

  /// Nil means the server has no stats endpoints and the caller should fall
  /// back to the actuator metrics.
  static func getServerStatsIfSupported(instanceId: String) async throws -> ServerStatsResponse? {
    guard isSupported(instanceId: instanceId) else { return nil }
    return try await getServerStats()
  }
}
