//
// SQLiteErrorLog.swift
//
//

import Foundation
import GRDB
import os

/// Routes SQLite's own error log into the app log. SQLite reports the failing
/// system call, path, and errno there, which the thrown `DatabaseError` omits.
nonisolated enum SQLiteErrorLog {
  // Persisting an entry writes to the log database, whose own failures come
  // back through this callback; the budget keeps that from feeding itself.
  private static let entryBudget = 200
  private static let remainingEntries = OSAllocatedUnfairLock(initialState: entryBudget)

  /// Must run before any SQLite connection opens; SQLite ignores it afterwards.
  static func install() {
    Database.logError = { resultCode, message in
      switch resultCode.primaryResultCode {
      case .SQLITE_NOTICE, .SQLITE_WARNING, .SQLITE_SCHEMA:
        return
      default:
        break
      }

      let isWithinBudget = remainingEntries.withLock { remaining in
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
      }
      guard isWithinBudget else { return }

      AppLogger(.database).error("SQLite log (\(resultCode.rawValue)): \(message)")
    }
  }
}
