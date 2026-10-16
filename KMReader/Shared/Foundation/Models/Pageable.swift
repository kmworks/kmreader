//
// Pageable.swift
//
//

import Foundation

nonisolated struct Pageable: Codable, Sendable {
  let sort: Sort
  let offset: Int
  let pageNumber: Int
  let pageSize: Int
  let paged: Bool
  let unpaged: Bool
}
