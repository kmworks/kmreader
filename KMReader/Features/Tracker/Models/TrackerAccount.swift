//
// TrackerAccount.swift
//

import Foundation

nonisolated struct TrackerAccount: Codable, Sendable {
  let loggedIn: Bool
  let username: String?

  enum CodingKeys: String, CodingKey {
    case loggedIn = "logged_in"
    case username
  }
}

nonisolated struct TrackerPreferences: Codable, Sendable {
  var libraries: [String]
  var defaultTracker: TrackerProvider?
}

nonisolated struct TrackerSearchItem: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let coverUrl: String?
  let description: String?
  let tracked: Bool
  let mediaType: String?
  let url: String?

  var remoteURL: URL? {
    url.flatMap(URL.init(string:))
  }
}

nonisolated struct TrackerRemoteState: Codable, Sendable {
  var score: Int?
  var status: TrackerStatus?
  var lastReadChapter: Double?
  var lastReadVolume: Int?
  var totalChapters: Int?
  var totalVolumes: Int?
  var startReadDate: String?
  var finishReadDate: String?
}

nonisolated enum TrackerStatus: String, CaseIterable, Codable, Sendable {
  case reading
  case planning
  case completed
  case paused
  case dropped
  case rereading

  var displayName: String {
    switch self {
    case .reading: return String(localized: "Reading")
    case .planning: return String(localized: "Planning")
    case .completed: return String(localized: "Completed")
    case .paused: return String(localized: "Paused")
    case .dropped: return String(localized: "Dropped")
    case .rereading: return String(localized: "Rereading")
    }
  }
}

nonisolated struct TrackerLedgerItem: Codable, Equatable, Identifiable, Sendable {
  let provider: TrackerProvider
  let trackId: String
  let title: String?
  let url: String?
  let coverUrl: String?
  let updatedAt: TimeInterval

  var id: String { "\(provider.rawValue):\(trackId)" }
  var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }
}
