//
// BookMetadataUpdate.swift
//
//

import Foundation

struct BookMetadataUpdate: Codable {
  var title: String
  var titleLock: Bool
  var summary: String
  var summaryLock: Bool
  var number: String
  var numberLock: Bool
  var numberSort: String
  var numberSortLock: Bool
  var releaseDate: Date?
  var releaseDateString: String
  var releaseDateLock: Bool
  var isbn: String
  var isbnLock: Bool
  var authors: [Author]
  var authorsLock: Bool
  var notableEntities: [NotableEntity]
  var notableEntitiesLock: Bool
  var tags: [String]
  var tagsLock: Bool
  var links: [WebLink]
  var linksLock: Bool

  static func from(_ book: Book) -> BookMetadataUpdate {
    var releaseDate: Date? = nil
    var releaseDateString: String = ""
    if let dateString = book.metadata.releaseDate, !dateString.isEmpty {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withFullDate]
      releaseDate = formatter.date(from: dateString)
      releaseDateString = dateString
    }

    return BookMetadataUpdate(
      title: book.metadata.title,
      titleLock: book.metadata.titleLock ?? false,
      summary: book.metadata.summary ?? "",
      summaryLock: book.metadata.summaryLock ?? false,
      number: book.metadata.number,
      numberLock: book.metadata.numberLock ?? false,
      numberSort: String(book.metadata.numberSort),
      numberSortLock: book.metadata.numberSortLock ?? false,
      releaseDate: releaseDate,
      releaseDateString: releaseDateString,
      releaseDateLock: book.metadata.releaseDateLock ?? false,
      isbn: book.metadata.isbn ?? "",
      isbnLock: book.metadata.isbnLock ?? false,
      authors: book.metadata.authors ?? [],
      authorsLock: book.metadata.authorsLock ?? false,
      notableEntities: book.metadata.notableEntities ?? [],
      notableEntitiesLock: book.metadata.notableEntitiesLock ?? false,
      tags: book.metadata.tags ?? [],
      tagsLock: book.metadata.tagsLock ?? false,
      links: book.metadata.links ?? [],
      linksLock: book.metadata.linksLock ?? false
    )
  }

  func toAPIDict(against original: Book) -> [String: Any] {
    var dict: [String: Any] = [:]

    if title != original.metadata.title {
      dict["title"] = title
    }
    dict["titleLock"] = titleLock

    if summary != (original.metadata.summary ?? "") {
      dict["summary"] = summary.isEmpty ? NSNull() : summary
    }
    dict["summaryLock"] = summaryLock

    if number != original.metadata.number {
      dict["number"] = number
    }
    dict["numberLock"] = numberLock

    if let numberSortDouble = Double(numberSort), numberSortDouble != original.metadata.numberSort {
      dict["numberSort"] = numberSortDouble
    }
    dict["numberSortLock"] = numberSortLock

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    let currentReleaseDateString = original.metadata.releaseDate ?? ""
    let newReleaseDateString = releaseDate.map { formatter.string(from: $0) } ?? ""

    if newReleaseDateString != currentReleaseDateString {
      dict["releaseDate"] = newReleaseDateString.isEmpty ? NSNull() : newReleaseDateString
    }
    dict["releaseDateLock"] = releaseDateLock

    if isbn != (original.metadata.isbn ?? "") {
      dict["isbn"] = isbn.isEmpty ? NSNull() : isbn
    }
    dict["isbnLock"] = isbnLock

    if authors != (original.metadata.authors ?? []) {
      dict["authors"] = authors.map { ["name": $0.name, "role": $0.role.rawValue] }
    }
    dict["authorsLock"] = authorsLock

    if notableEntities != (original.metadata.notableEntities ?? []) {
      dict["notableEntities"] = notableEntities.map { ["kind": $0.kind, "name": $0.name] }
    }
    dict["notableEntitiesLock"] = notableEntitiesLock

    if tags != (original.metadata.tags ?? []) {
      dict["tags"] = tags
    }
    dict["tagsLock"] = tagsLock

    if links != (original.metadata.links ?? []) {
      dict["links"] = links.map { ["label": $0.label, "url": $0.url] }
    }
    dict["linksLock"] = linksLock

    return dict
  }
}
