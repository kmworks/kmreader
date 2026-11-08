//
// ServerProfileService.swift
//
//

import Foundation

/// Reads what the server offers beyond Komga (`/api/v1/server/info` features
/// and the skip-read setting) after login, server switch and each user load,
/// so kmrs-private requests are made only where they can succeed.
nonisolated enum ServerProfileService {
  private static let apiClient = APIClient.shared
  private static let logger = AppLogger(.api)

  /// Nil until the instance's first successful refresh.
  static func profile(instanceId: String) -> ServerProfile? {
    AppConfig.serverProfiles.profile(instanceId: instanceId)
  }

  static func supports(_ feature: ServerFeature, instanceId: String) -> Bool {
    profile(instanceId: instanceId)?.supports(feature) == true
  }

  static func isKmrs(instanceId: String) -> Bool {
    profile(instanceId: instanceId)?.isKmrs == true
  }

  static func skipsReadOnNext(instanceId: String) -> Bool {
    profile(instanceId: instanceId)?.skipReadOnNext == true
  }

  /// Runs with the user load, so like it bypasses the offline check: it decides
  /// whether the app goes back online. A failed request keeps the last known
  /// profile, which offline reading still needs for the skip-read setting.
  @concurrent
  static func refresh(instanceId: String) async {
    guard !instanceId.isEmpty else { return }
    let info: NativeServerInfo?
    do {
      info = try await fetchInfo()
    } catch {
      logger.debug("Server info unavailable: \(error.localizedDescription)")
      return
    }

    let profile: ServerProfile
    if let info {
      let skipReadOnNext = await fetchSkipReadOnNext() ?? skipsReadOnNext(instanceId: instanceId)
      profile = ServerProfile(
        isKmrs: true,
        features: Set((info.features ?? []).compactMap(ServerFeature.init(rawValue:))),
        skipReadOnNext: skipReadOnNext
      )
    } else {
      profile = .komga
    }

    var profiles = AppConfig.serverProfiles
    guard profiles.profile(instanceId: instanceId) != profile else { return }
    profiles.set(profile, instanceId: instanceId)
    AppConfig.serverProfiles = profiles
  }

  /// Nil for Komga, which answers 404.
  private static func fetchInfo() async throws -> NativeServerInfo? {
    do {
      let info: NativeServerInfo = try await apiClient.request(
        path: "/api/v1/server/info",
        bypassOfflineCheck: true,
        timeout: AppConfig.authTimeout
      )
      return info
    } catch APIError.notFound {
      return nil
    }
  }

  private static func fetchSkipReadOnNext() async -> Bool? {
    do {
      let settings: ServerSettingsResponse = try await apiClient.request(
        path: "/api/v1/settings",
        bypassOfflineCheck: true,
        timeout: AppConfig.authTimeout
      )
      return settings.skipReadOnNext ?? false
    } catch {
      logger.debug("Server settings unavailable: \(error.localizedDescription)")
      return nil
    }
  }
}
