//
// ServerUpdateCheck.swift
//

import Foundation

nonisolated struct ServerUpdateCheck: Decodable, Sendable {
  let enabled: Bool
  let checkedAt: Date?
  let update: Update?

  nonisolated struct Update: Decodable, Sendable {
    let version: String
    let url: String
    let releaseDate: Date?

    var releaseURL: URL? {
      URL(string: url)
    }
  }
}
