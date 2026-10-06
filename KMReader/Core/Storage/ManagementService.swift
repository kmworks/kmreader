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
