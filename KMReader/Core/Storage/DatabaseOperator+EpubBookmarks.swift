//
// DatabaseOperator+EpubBookmarks.swift
//
//

import Foundation
import GRDB

extension DatabaseOperator {
  func fetchEpubBookmarks(instanceId: String, bookId: String) throws -> [EpubBookmark] {
    try read { db in
      try EpubBookmark
        .filter(Column("instance_id") == instanceId)
        .filter(Column("book_id") == bookId)
        .fetchAll(db)
        .sorted { lhs, rhs in
          if lhs.chapterIndex != rhs.chapterIndex {
            return lhs.chapterIndex < rhs.chapterIndex
          }
          return lhs.chapterFraction < rhs.chapterFraction
        }
    }
  }

  func saveEpubBookmark(_ bookmark: EpubBookmark) throws {
    try write { db in
      try save(bookmark, db: db)
    }
  }

  func deleteEpubBookmark(id: UUID) throws {
    _ = try write { db in
      try EpubBookmark.deleteOne(db, key: id)
    }
  }
}
