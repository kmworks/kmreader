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
  let mediaType: TrackerMediaType?
  let series: Bool
  let url: String?

  init(
    id: String,
    title: String,
    coverUrl: String? = nil,
    description: String? = nil,
    tracked: Bool = false,
    mediaType: TrackerMediaType? = nil,
    series: Bool = false,
    url: String? = nil
  ) {
    self.id = id
    self.title = title
    self.coverUrl = coverUrl
    self.description = description
    self.tracked = tracked
    self.mediaType = mediaType
    self.series = series
    self.url = url
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    tracked = try container.decodeIfPresent(Bool.self, forKey: .tracked) ?? false
    mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
      .flatMap(TrackerMediaType.init(rawValue:))
    series = try container.decodeIfPresent(Bool.self, forKey: .series) ?? false
    url = try container.decodeIfPresent(String.self, forKey: .url)
  }

  var remoteURL: URL? {
    url.flatMap(URL.init(string:))
  }

  var kindLabel: String? {
    if series {
      switch mediaType {
      case .manga: return String(localized: "Manga Series")
      case .novel: return String(localized: "Novel Series")
      case nil: return String(localized: "Series")
      }
    }
    switch mediaType {
    case .manga: return String(localized: "Manga")
    case .novel: return String(localized: "Novel")
    case nil: return nil
    }
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
