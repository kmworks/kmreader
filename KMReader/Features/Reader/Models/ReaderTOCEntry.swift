//
// ReaderTOCEntry.swift
//
//

import Foundation

struct ReaderTOCEntry: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  let title: String
  let pageIndex: Int
  let children: [ReaderTOCEntry]?

  nonisolated var pageNumber: String {
    "\( pageIndex + 1)"
  }

  nonisolated init(title: String, pageIndex: Int, children: [ReaderTOCEntry]? = nil) {
    self.id = UUID()
    self.title = title
    self.pageIndex = pageIndex
    self.children = children
  }
}
