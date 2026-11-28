//
// ServerEndpointProbeService.swift
//

import Foundation

/// Stateless health and latency probe for a single server endpoint.
/// Uses an ephemeral session and never touches `AppConfig.current` or the
/// shared offline failure tracker.
nonisolated enum ServerEndpointProbeService {
  private static let logger = AppLogger(.api)

  static func probe(
    endpoint: ServerEndpoint,
    authToken: String,
    authMethod: AuthenticationMethod,
    sessionToken: String? = nil,
    timeout: TimeInterval = 5.0
  ) async -> ServerEndpointProbeStatus? {
    let baseURL = endpoint.normalizedURL
    guard !baseURL.isEmpty, let url = URL(string: baseURL + "/api/v2/users/me") else {
      return .unreachable
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = timeout
    if !AppConfig.userAgent.isEmpty {
      request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
    }

    // Mirror `APIClient.applyAuthHeaders` for API-key instances whose session
    // was created by that key: Komga skips key re-authentication (and the
    // authentication activity row) while the session token is valid, and
    // falls back to the key once it expires.
    if authMethod == .apiKey, let sessionToken, !sessionToken.isEmpty {
      request.setValue(sessionToken, forHTTPHeaderField: "X-Auth-Token")
      if !authToken.isEmpty {
        request.setValue(authToken, forHTTPHeaderField: "X-API-Key")
      }
    } else if !authToken.isEmpty {
      switch authMethod {
      case .basicAuth:
        request.setValue("Basic \(authToken)", forHTTPHeaderField: "Authorization")
      case .apiKey:
        request.setValue(authToken, forHTTPHeaderField: "X-API-Key")
      }
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }

    let clock = ContinuousClock()
    let start = clock.now
    do {
      let (data, response) = try await session.data(for: request)
      guard !Task.isCancelled else { return nil }
      guard let httpResponse = response as? HTTPURLResponse else { return .unreachable }
      let elapsed = clock.now - start
      let milliseconds = max(
        1,
        Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
      )
      switch httpResponse.statusCode {
      case 200...299:
        // A 200 from a reverse-proxy fallback, SSO login page, or unrelated
        // service is not a healthy Komga endpoint; require a valid user DTO.
        guard (try? JSONDecoder().decode(User.self, from: data)) != nil else {
          logger.warning("⚠️ Probe got non-Komga 200 response from \(baseURL)")
          return .unreachable
        }
        return .reachable(milliseconds: milliseconds)
      case 401, 403:
        return .unauthorized
      default:
        return .unreachable
      }
    } catch {
      return Task.isCancelled ? nil : .unreachable
    }
  }
}
