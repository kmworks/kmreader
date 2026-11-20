//
// BookBatchMetadataRow.swift
//
//

import Foundation

struct BookBatchMetadataRow {
  let book: Book
  var values: BookMetadataUpdate
  var dirtyFields: Set<PerBookMetadataField> = []
  var touchedLocks: Set<PerBookMetadataField> = []

  init(book: Book) {
    self.book = book
    values = BookMetadataUpdate.from(book)
  }
}
