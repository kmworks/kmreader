//
// SyncPhase.swift
//
//

import Foundation

nonisolated enum SyncPhase: Sendable {
  case libraries
  case collections
  case series
  case readLists
  case books
}
