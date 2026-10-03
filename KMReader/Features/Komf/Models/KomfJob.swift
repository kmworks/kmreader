//
// KomfJob.swift
//
//

import Foundation

nonisolated struct KomfJob: Codable, Equatable, Sendable {
  enum Status: String, Codable, Sendable {
    case running = "RUNNING"
    case failed = "FAILED"
    case completed = "COMPLETED"
  }

  let seriesId: String
  let id: String
  let status: Status
  let message: String?
  let startedAt: Date
  let finishedAt: Date?
}
