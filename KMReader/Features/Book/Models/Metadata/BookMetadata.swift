//
// BookMetadata.swift
//
//

import Foundation

nonisolated struct BookMetadata: Codable, Equatable, Hashable, Sendable {
  static let empty = BookMetadata(
    created: nil,
    lastModified: nil,
    title: "",
    titleLock: nil,
    summary: nil,
    summaryLock: nil,
    number: "",
    numberLock: nil,
    numberSort: 0,
    numberSortLock: nil,
    releaseDate: nil,
    releaseDateLock: nil,
    authors: nil,
    authorsLock: nil,
    notableEntities: nil,
    notableEntitiesLock: nil,
    tags: nil,
    tagsLock: nil,
    isbn: nil,
    isbnLock: nil,
    links: nil,
    linksLock: nil
  )

  let created: String?
  let lastModified: String?
  let title: String
  let titleLock: Bool?
  let summary: String?
  let summaryLock: Bool?
  let number: String
  let numberLock: Bool?
  let numberSort: Double
  let numberSortLock: Bool?
  let releaseDate: String?
  let releaseDateLock: Bool?
  let authors: [Author]?
  let authorsLock: Bool?
  let notableEntities: [NotableEntity]?
  let notableEntitiesLock: Bool?
  let tags: [String]?
  let tagsLock: Bool?
  let isbn: String?
  let isbnLock: Bool?
  let links: [WebLink]?
  let linksLock: Bool?
}
