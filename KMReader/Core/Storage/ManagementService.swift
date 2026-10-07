//
// ManagementService.swift
//
//

import Foundation

nonisolated enum ManagementService {
  private static let apiClient = APIClient.shared

  static func getMetric(_ metricName: String, tags: [MetricTag]? = nil) async throws -> Metric {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    let path = "/actuator/metrics/\(metricName)"
    var queryItems: [URLQueryItem]?

    if let tags = tags, !tags.isEmpty {
      queryItems = tags.map { URLQueryItem(name: "tag", value: "\($0.key):\($0.value)") }
    }

    return try await apiClient.request(path: path, queryItems: queryItems)
  }

  /// `getMetric` with 404 softened to nil: a missing meter is genuinely
  /// absent, anything else is a real failure.
  static func getMetricOptional(_ metricName: String, tags: [MetricTag]? = nil) async throws
    -> Metric?
  {
    do {
      return try await getMetric(metricName, tags: tags)
    } catch let error as APIError {
      guard case .notFound = error else { throw error }
      return nil
    }
  }

  static func getInfo() async throws -> ActuatorInfoResponse {
    try await apiClient.request(path: "/actuator/info")
  }

  static func getHealth() async throws -> ActuatorHealthResponse {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    return try await apiClient.request(path: "/actuator/health")
  }

  static func getScheduledTasks() async throws -> ActuatorScheduledTasksResponse {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    return try await apiClient.request(path: "/actuator/scheduledtasks")
  }

  static func getSessions() async throws -> ActuatorSessionsResponse {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    return try await apiClient.request(path: "/actuator/sessions")
  }

  /// Spring's per-user variant: the username is a required query parameter
  /// (400 when absent). kmrs answers the same request, and also accepts an
  /// absent username for the cross-user listing in `getSessions`.
  static func getSessions(username: String) async throws -> ActuatorSessionsResponse {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    return try await apiClient.request(
      path: "/actuator/sessions",
      queryItems: [URLQueryItem(name: "username", value: username)]
    )
  }

  static func deleteSession(id: String) async throws {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    let _: EmptyResponse = try await apiClient.request(
      path: "/actuator/sessions/\(id)",
      method: "DELETE"
    )
  }

  static func shutdown() async throws {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    let _: EmptyResponse = try await apiClient.request(
      path: "/actuator/shutdown",
      method: "POST"
    )
  }

  static func downloadLogFile(destinationURL: URL) async throws {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    _ = try await apiClient.requestFileWithProgress(
      path: "/actuator/logfile",
      progressKey: "serverLogfile",
      destinationURL: destinationURL
    )
  }

  /// HEAD probe for the logfile endpoint: 404 means the server exposes no log
  /// file (Komga without `logging.file.name`), so the button stays hidden.
  static func isLogfileAvailable() async throws -> Bool {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    do {
      let _: EmptyResponse = try await apiClient.request(path: "/actuator/logfile", method: "HEAD")
      return true
    } catch let error as APIError {
      guard case .notFound = error else { throw error }
      return false
    }
  }

  static func cancelAllTasks() async throws {
    guard AppConfig.current.isAdmin else {
      throw AppErrorType.operationNotAllowed(message: "Admin access required")
    }
    let _: EmptyResponse = try await apiClient.request(
      path: "/api/v1/tasks",
      method: "DELETE"
    )
  }
}
