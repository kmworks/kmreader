//
// ServerStatsResponse.swift
//
//

import Foundation

/// `GET /api/v1/stats/server` (kmrs-private, admin only): per-type task
/// execution metrics, process stats, and global totals.
nonisolated struct ServerStatsResponse: Decodable, Sendable {
  let tasks: TaskStats
  let process: ProcessStats
  let totals: Totals

  struct TaskStats: Decodable, Sendable {
    let types: [TaskTypeStats]
  }

  struct TaskTypeStats: Decodable, Sendable {
    let type: String
    let executions: Double
    let totalTimeMs: Double
    let failures: Double
  }

  struct ProcessStats: Decodable, Sendable {
    /// `yyyy-MM-dd'T'HH:mm:ss'Z'`.
    let startTime: String
    let uptimeSeconds: Double
    /// Percent of total CPU capacity (100 = every core busy).
    let cpuUsage: Double
    let memoryBytes: Double
  }

  struct Totals: Decodable, Sendable {
    let libraries: Double
    let collections: Double
    let readlists: Double
    let sidecars: Double
  }
}
