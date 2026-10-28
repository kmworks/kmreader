//
// SeriesBooksMetadata.swift
//
//

import Foundation

nonisolated struct SeriesBooksMetadata: Codable, Equatable, Hashable, Sendable {
  static let empty = SeriesBooksMetadata(
    created: nil,
    lastModified: nil,
    authors: nil,
    notableEntities: nil,
    tags: nil,
    releaseDate: nil,
    summary: nil,
    summaryNumber: nil
  )

  let created: String?
  let lastModified: String?
  let authors: [Author]?
  let notableEntities: [NotableEntity]?
  let tags: [String]?
  let releaseDate: String?
  let summary: String?
  let summaryNumber: String?
}
