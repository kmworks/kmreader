//
// ServerFeature.swift
//
//

import Foundation

/// A kmrs-private feature named in `features` on `/api/v1/server/info`. kmrs
/// lists a feature that needs setup (komf, update check) only once it is set up.
nonisolated enum ServerFeature: String, Codable, CaseIterable, Sendable {
  case serverStats
  case readingStats
  case smartLists
  case sessions
  case komf
  case trackers
  case updateCheck
}
