//
// ServerProfileService.swift
//
//

import Foundation

/// Reads what the server offers beyond Komga (`/api/v1/server/info` features
/// and the kmrs settings every user can read) after login, server switch and
/// each user load, so kmrs-private requests are made only where they can succeed.
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

  static func recentReadingCutoff(instanceId: String) -> Date? {
    profile(instanceId: instanceId)?.recentReadingCutoff()
  }

  /// Runs with the user load, so like it bypasses the offline check: it decides
  /// whether the app goes back online. A failed request keeps the last known
  /// profile, which offline reading still needs for the kmrs settings.
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
      let previous = Self.profile(instanceId: instanceId)
      let skipReadOnNext: Bool
      let recentReadingDays: Int
      if let settings = await fetchSettings() {
        skipReadOnNext = settings.skipReadOnNext ?? false
        recentReadingDays = max(0, settings.recentReadingDays ?? 0)
      } else {
        skipReadOnNext = previous?.skipReadOnNext ?? false
        recentReadingDays = previous?.recentReadingDays ?? 0
      }
      profile = ServerProfile(
        isKmrs: true,
        features: Set((info.features ?? []).compactMap(ServerFeature.init(rawValue:))),
        skipReadOnNext: skipReadOnNext,
        recentReadingDays: recentReadingDays
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

  /// Nil when the request failed, so the last known values stay.
  private static func fetchSettings() async -> ServerSettingsResponse? {
    do {
      let settings: ServerSettingsResponse = try await apiClient.request(
        path: "/api/v1/settings",
        bypassOfflineCheck: true,
        timeout: AppConfig.authTimeout
      )
      return settings
    } catch {
      logger.debug("Server settings unavailable: \(error.localizedDescription)")
      return nil
    }
  }
}
