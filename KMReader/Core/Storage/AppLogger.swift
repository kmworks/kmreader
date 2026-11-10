//
// AppLogger.swift
//
//

import Foundation
import OSLog
import SwiftUI

enum LogCategory: String, CaseIterable, Sendable {
  case app = "App"
  case api = "API"
  case auth = "Auth"
  case sync = "Sync"
  case sse = "SSE"
  case database = "Database"
  case offline = "Offline"
  case cache = "Cache"
  case reader = "Reader"
  case dashboard = "Dashboard"
  case notification = "Notification"
}

nonisolated enum LogLevel: String, CaseIterable, Sendable {
  case debug = "DEBUG"
  case info = "INFO"
  case warning = "WARNING"
  case error = "ERROR"

  init(_ level: String) {
    self = LogLevel(rawValue: level.uppercased()) ?? .info
  }

  init(_ priority: Int) {
    self = LogLevel.allCases.first { $0.priority == priority } ?? .info
  }

  var priority: Int {
    switch self {
    case .debug: return 1
    case .info: return 2
    case .warning: return 3
    case .error: return 4
    }
  }

  var color: Color {
    switch self {
    case .debug: return .secondary
    case .info: return .blue
    case .warning: return .orange
    case .error: return .red
    }
  }
}

/// Unified logger that writes to both OSLog and SQLite storage
struct AppLogger: Sendable {
  static let shared = AppLogger(.app)

  private let osLogger: Logger
  private let category: LogCategory

  nonisolated init(_ category: LogCategory) {
    self.category = category
    self.osLogger = Logger(subsystem: "com.everpcpc.kmreader", category: category.rawValue)
  }

  nonisolated func debug(_ message: String) {
    osLogger.debug("\(message, privacy: .public)")
    Task {
      await LogStore.shared.insert(
        date: Date(), level: LogLevel.debug.priority,
        category: category.rawValue, message: message)
    }
  }

  nonisolated func info(_ message: String) {
    osLogger.info("\(message, privacy: .public)")
    Task {
      await LogStore.shared.insert(
        date: Date(), level: LogLevel.info.priority,
        category: category.rawValue, message: message)
    }
  }

  nonisolated func warning(_ message: String) {
    osLogger.warning("\(message, privacy: .public)")
    Task {
      await LogStore.shared.insert(
        date: Date(), level: LogLevel.warning.priority,
        category: category.rawValue, message: message)
    }
  }

  nonisolated func error(_ message: String) {
    osLogger.error("\(message, privacy: .public)")
    Task {
      await LogStore.shared.insert(
        date: Date(), level: LogLevel.error.priority,
        category: category.rawValue, message: message)
    }
  }
}
