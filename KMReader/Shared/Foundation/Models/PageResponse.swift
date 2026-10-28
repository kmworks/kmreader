//
// PageResponse.swift
//

import Foundation

nonisolated struct PageResponse<T: Decodable & Sendable>: Decodable, Sendable {
  let content: [T]
  let page: Int
  let size: Int
  let totalElements: Int
  let totalPages: Int
  let first: Bool
  let last: Bool
}
