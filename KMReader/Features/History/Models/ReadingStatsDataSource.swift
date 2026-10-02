//
// ReadingStatsDataSource.swift
//
//

import Foundation

nonisolated enum ReadingStatsDataSource: String, Codable, Sendable {
  case server
  case local
}
