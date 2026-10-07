//
// SmartListShareTarget.swift
//
//

import Foundation

/// A user eligible as a share target for SHARED smart lists; the directory is admin-only.
nonisolated struct SmartListShareTarget: Codable, Identifiable, Sendable, Equatable, Hashable {
  let id: String
  let email: String
}
