//
// ReadingStatsSummary.swift
//
//

import Foundation

nonisolated struct ReadingStatsSummary: Codable, Equatable, Sendable {
  let totalBooks: Double
  let booksStartedReading: Double
  let booksCompletedReading: Double
  let totalPagesRead: Double
  let averagePagesPerBook: Double
  let readingDays: Double
  let estimatedReadingHours: Double
  let lastReadAt: String?
  // Only the server stats endpoints compute streaks; the local aggregation leaves them nil.
  let currentStreakDays: Double?
  let longestStreakDays: Double?

  init(
    totalBooks: Double = 0,
    booksStartedReading: Double = 0,
    booksCompletedReading: Double = 0,
    totalPagesRead: Double = 0,
    averagePagesPerBook: Double = 0,
    readingDays: Double = 0,
    estimatedReadingHours: Double = 0,
    lastReadAt: String? = nil,
    currentStreakDays: Double? = nil,
    longestStreakDays: Double? = nil
  ) {
    self.totalBooks = totalBooks
    self.booksStartedReading = booksStartedReading
    self.booksCompletedReading = booksCompletedReading
    self.totalPagesRead = totalPagesRead
    self.averagePagesPerBook = averagePagesPerBook
    self.readingDays = readingDays
    self.estimatedReadingHours = estimatedReadingHours
    self.lastReadAt = lastReadAt
    self.currentStreakDays = currentStreakDays
    self.longestStreakDays = longestStreakDays
  }

  private enum CodingKeys: String, CodingKey {
    case totalBooks
    case totalBookCount
    case booksTotal

    case booksStartedReading
    case booksStarted
    case startedBooks
    case booksWithProgress

    case booksCompletedReading
    case booksCompleted
    case completedBooks

    case totalPagesRead
    case pagesRead

    case averagePagesPerBook
    case avgPagesPerBook

    case readingDays
    case readingStreak
    case activeReadingDays

    case estimatedReadingHours
    case estimatedReadingTime
    case readingHours

    case lastReadAt
    case lastReadDate

    case currentStreakDays
    case longestStreakDays
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    totalBooks = try container.decodeFirstDouble(forKeys: [.totalBooks, .totalBookCount, .booksTotal]) ?? 0

    booksStartedReading =
      try container.decodeFirstDouble(forKeys: [.booksStartedReading, .booksStarted, .startedBooks, .booksWithProgress])
      ?? 0

    booksCompletedReading =
      try container.decodeFirstDouble(forKeys: [.booksCompletedReading, .booksCompleted, .completedBooks]) ?? 0

    totalPagesRead = try container.decodeFirstDouble(forKeys: [.totalPagesRead, .pagesRead]) ?? 0

    averagePagesPerBook =
      try container.decodeFirstDouble(forKeys: [.averagePagesPerBook, .avgPagesPerBook])
      ?? 0

    readingDays =
      try container.decodeFirstDouble(forKeys: [.readingDays, .readingStreak, .activeReadingDays]) ?? 0

    estimatedReadingHours =
      try container.decodeFirstDouble(forKeys: [.estimatedReadingHours, .estimatedReadingTime, .readingHours])
      ?? 0

    lastReadAt = try container.decodeFirstString(forKeys: [.lastReadAt, .lastReadDate])

    currentStreakDays = try container.decodeFirstDouble(forKeys: [.currentStreakDays])
    longestStreakDays = try container.decodeFirstDouble(forKeys: [.longestStreakDays])
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(totalBooks, forKey: .totalBooks)
    try container.encode(booksStartedReading, forKey: .booksStartedReading)
    try container.encode(booksCompletedReading, forKey: .booksCompletedReading)
    try container.encode(totalPagesRead, forKey: .totalPagesRead)
    try container.encode(averagePagesPerBook, forKey: .averagePagesPerBook)
    try container.encode(readingDays, forKey: .readingDays)
    try container.encode(estimatedReadingHours, forKey: .estimatedReadingHours)
    try container.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
    try container.encodeIfPresent(currentStreakDays, forKey: .currentStreakDays)
    try container.encodeIfPresent(longestStreakDays, forKey: .longestStreakDays)
  }
}
