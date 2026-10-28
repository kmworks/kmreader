//
// MetadataFilterItemSource.swift
//
//

import Foundation

enum MetadataFilterItemSource: Sendable {
  case publishers
  case authors(seriesId: String?, libraryIds: [String]?, collectionId: String?, readListId: String?)
  case genres(libraryIds: [String]?, collectionId: String?)
  case tags(seriesId: String?, readListId: String?, libraryIds: [String]?, collectionId: String?)
  case languages(libraryIds: [String]?, collectionId: String?)
  case ageRatings(libraryIds: [String]?, collectionId: String?)
  case releaseYears(libraryIds: [String]?, collectionId: String?)
  case notableEntities(
    libraryIds: [String]?, collectionId: String?, seriesId: String?, readListId: String?)

  func load() async throws -> [String] {
    switch self {
    case .publishers:
      return try await ReferentialService.getPublishers()
    case .authors(let seriesId, let libraryIds, let collectionId, let readListId):
      return try await ReferentialService.getAuthorsNames(
        seriesId: seriesId,
        libraryIds: libraryIds,
        collectionId: collectionId,
        readListId: readListId
      )
    case .genres(let libraryIds, let collectionId):
      return try await ReferentialService.getGenres(
        libraryIds: libraryIds,
        collectionId: collectionId
      )
    case .tags(let seriesId, let readListId, let libraryIds, let collectionId):
      if seriesId != nil || readListId != nil {
        return try await ReferentialService.getBookTags(
          seriesId: seriesId,
          readListId: readListId,
          libraryIds: libraryIds
        )
      }
      return try await ReferentialService.getTags(
        libraryIds: libraryIds,
        collectionId: collectionId
      )
    case .languages(let libraryIds, let collectionId):
      return try await ReferentialService.getLanguages(
        libraryIds: libraryIds,
        collectionId: collectionId
      )
    case .ageRatings(let libraryIds, let collectionId):
      return try await ReferentialService.getAgeRatings(
        libraryIds: libraryIds,
        collectionId: collectionId
      )
    case .notableEntities(let libraryIds, let collectionId, let seriesId, let readListId):
      let entities = try await ReferentialService.getNotableEntities(
        libraryIds: libraryIds,
        collectionId: collectionId,
        seriesId: seriesId,
        readListId: readListId
      )
      return entities.map(\.filterKey)
    case .releaseYears(let libraryIds, let collectionId):
      return try await ReferentialService.getReleaseYears(
        libraryIds: libraryIds,
        collectionId: collectionId
      )
    }
  }
}
