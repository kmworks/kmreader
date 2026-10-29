//
// TrackerLink.swift
//

import Foundation

nonisolated enum TrackerMode: String, CaseIterable, Codable, Sendable {
  case auto
  case chapter
  case volume

  var displayName: String {
    switch self {
    case .auto: return String(localized: "Auto")
    case .chapter: return String(localized: "Chapter")
    case .volume: return String(localized: "Volume")
    }
  }
}

nonisolated struct TrackerLink: Codable, Equatable, Identifiable, Sendable {
  let seriesId: String
  let provider: TrackerProvider
  let trackId: String
  let title: String?
  let trackMode: TrackerMode
  let chapterOffset: Int
  let createdDate: String
  let lastModifiedDate: String

  var id: String { "\(seriesId):\(provider.rawValue)" }
  var displayTitle: String { title ?? trackId }
}

nonisolated struct TrackerLinkGroup: Codable, Equatable, Identifiable, Sendable {
  let seriesId: String
  let links: [TrackerLink]

  var id: String { seriesId }
}

nonisolated struct TrackerLinkCounts: Codable, Sendable {
  let series: Int
  let providers: [String: Int]
}

nonisolated struct TrackerLinkPage: Codable, Sendable {
  let content: [TrackerLinkGroup]
  let pageable: Pageable
  let totalElements: Int
  let totalPages: Int
  let last: Bool
  let size: Int
  let number: Int
  let numberOfElements: Int
  let first: Bool
  let empty: Bool
  let counts: TrackerLinkCounts

  var page: Page<TrackerLinkGroup> {
    Page(
      content: content,
      pageable: pageable,
      totalElements: totalElements,
      totalPages: totalPages,
      last: last,
      size: size,
      number: number,
      numberOfElements: numberOfElements,
      first: first,
      empty: empty
    )
  }
}
