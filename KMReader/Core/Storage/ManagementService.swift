//
// ManagementService.swift
//
//

import Foundation

nonisolated enum ManagementService {
  private static let apiClient = APIClient.shared

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
