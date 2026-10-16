//
// Page.swift
//
//

import Foundation

nonisolated struct Page<T: Codable & Sendable>: Codable, Sendable {
  let content: [T]
  let pageable: Pageable
  let totalElements: Int
  let totalPages: Int
  let last: Bool
  let size: Int
  let number: Int
  let numberOfElements: Int
  let first: Bool
  let empty: Bool
}
