//
// KomgaLibrary.swift
//

import Foundation

nonisolated struct KomgaLibrary: Codable, Equatable, Sendable {
  static let allLibrariesId = "__all_libraries__"

  var id: UUID
  var instanceId: String
  var libraryId: String
  var name: String
  var createdAt: Date
  var fileSize: Double?
  var booksCount: Double?
  var seriesCount: Double?
  var sidecarsCount: Double?

  init(
    id: UUID = UUID(),
    instanceId: String,
    libraryId: String,
    name: String,
    createdAt: Date = Date(),
    fileSize: Double? = nil,
    booksCount: Double? = nil,
    seriesCount: Double? = nil,
    sidecarsCount: Double? = nil
  ) {
    self.id = id
    self.instanceId = instanceId
    self.libraryId = libraryId
    self.name = name
    self.createdAt = createdAt
    self.fileSize = fileSize
    self.booksCount = booksCount
    self.seriesCount = seriesCount
    self.sidecarsCount = sidecarsCount
  }
}
