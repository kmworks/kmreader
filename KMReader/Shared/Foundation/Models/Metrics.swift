//
// Metrics.swift
//
//

import Foundation

nonisolated struct Metric: Codable, Sendable {
  let name: String
  let description: String?
  let baseUnit: String?
  let measurements: [Measurement]
  let availableTags: [TagInfo]?

  struct Measurement: Codable, Sendable {
    let statistic: String
    let value: Double
  }

  struct TagInfo: Codable, Sendable {
    let tag: String
    let values: [String]
  }
}

nonisolated struct MetricTag: Codable, Sendable {
  let key: String
  let value: String
}

/// Actuator metrics used as the library-metrics fallback on servers without
/// the kmrs stats endpoints; only library size/series/books are consumed.
nonisolated enum MetricName: String, Sendable {
  case booksFileSize = "komga.books.filesize"
  case series = "komga.series"
  case books = "komga.books"
}
