//
// ServerSettingsService.swift
//
//

import Foundation

nonisolated enum ServerSettingsService {
  private static let apiClient = APIClient.shared
  private static let logger = AppLogger(.api)

  /// Refreshes the local copy of the server's skip-read setting. A failed
  /// request keeps the last known value: offline reading still needs it.
  static func refreshSkipReadOnNext(instanceId: String) async {
    guard !instanceId.isEmpty else { return }
    do {
      let settings: ServerSettingsResponse = try await apiClient.request(path: "/api/v1/settings")
      var store = AppConfig.serverSkipReadOnNext
      store.set(settings.skipReadOnNext ?? false, instanceId: instanceId)
      AppConfig.serverSkipReadOnNext = store
    } catch {
      logger.debug("Server settings unavailable: \(error.localizedDescription)")
    }
  }
}
