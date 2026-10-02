//
// ReadingStatsService.swift
//
//

import Foundation

nonisolated enum ReadingStatsService {
  private static let apiClient = APIClient.shared
  private static let logger = AppLogger(.api)

  // An unsupported verdict expires after this interval so a server upgrade is picked up.
  private static let capabilityRecheckInterval: TimeInterval = 24 * 60 * 60

  @concurrent
  static func fetchReadingStats(libraryId: String?) async throws -> (
    payload: ReadingStatsPayload, dataSource: ReadingStatsDataSource
  ) {
    let normalizedLibraryId = normalizeLibraryId(libraryId)
    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else {
      return (.empty, .local)
    }

    if shouldQueryServer(instanceId: instanceId) {
      do {
        let payload = try await fetchServerPayload(libraryId: normalizedLibraryId)
        recordServerCapability(instanceId: instanceId, supported: true)
        return (payload, .server)
      } catch let error as APIError {
        guard case .notFound = error else { throw error }
        // The server lost the endpoints (e.g. downgrade): remember and fall back to local.
        recordServerCapability(instanceId: instanceId, supported: false)
        logger.info("Server reading stats unavailable, falling back to local stats")
      }
    }

    return (await fetchLocalPayload(instanceId: instanceId, libraryId: normalizedLibraryId), .local)
  }

  private static func shouldQueryServer(instanceId: String) -> Bool {
    guard !AppConfig.isOffline else { return false }
    guard let record = AppConfig.serverReadingStatsCapability.record(instanceId: instanceId) else {
      return true
    }
    if record.supported { return true }
    return Date().timeIntervalSince(record.checkedAt) >= capabilityRecheckInterval
  }

  private static func recordServerCapability(instanceId: String, supported: Bool) {
    var capability = AppConfig.serverReadingStatsCapability
    // A repeated supported verdict is not worth a UserDefaults round-trip; an
    // unsupported verdict must always refresh checkedAt, it throttles re-probes.
    guard !(supported && capability.record(instanceId: instanceId)?.supported == true) else { return }
    capability.upsert(instanceId: instanceId, supported: supported, checkedAt: Date())
    AppConfig.serverReadingStatsCapability = capability
  }

  // MARK: - Server Stats

  private static func fetchServerPayload(libraryId: String?) async throws -> ReadingStatsPayload {
    var libraryQuery: [URLQueryItem] = []
    if let libraryId {
      libraryQuery.append(URLQueryItem(name: "libraryId", value: libraryId))
    }
    let activityQuery =
      libraryQuery + [URLQueryItem(name: "tzOffsetMinutes", value: "\(TimeZone.current.secondsFromGMT() / 60)")]

    async let summaryTask: ServerReadingSummaryResponse = apiClient.request(
      path: "/api/v1/stats/reading/summary",
      queryItems: libraryQuery.isEmpty ? nil : libraryQuery
    )
    async let activityTask: ServerReadingActivityResponse = apiClient.request(
      path: "/api/v1/stats/reading/activity",
      queryItems: activityQuery
    )
    async let topsTask: ServerReadingTopsResponse = apiClient.request(
      path: "/api/v1/stats/reading/tops",
      queryItems: libraryQuery.isEmpty ? nil : libraryQuery
    )

    let summary = try await summaryTask
    let activity = try await activityTask
    let tops = try await topsTask

    return ReadingStatsPayload(
      summary: summary.summary,
      statusDistribution: mapStatusDistribution(summary.statusDistribution),
      dailyDistribution: mapWeekdayDistribution(activity.weekdayDistribution),
      hourlyDistribution: mapHourlyDistribution(activity.hourlyDistribution),
      readingTimeSeries: activity.readingTimeSeries,
      topAuthors: tops.topAuthors,
      topGenres: tops.topGenres,
      topTags: tops.topTags,
      genreDistribution: tops.genreDistribution,
      tagDistribution: tops.tagDistribution,
      generatedAt: summary.generatedAt
    )
  }

  // Server status names map onto the same localized labels the local aggregation uses.
  private static func mapStatusDistribution(_ items: [ReadingStatsItem]) -> [ReadingStatsItem] {
    items
      .map { item in
        let localizedName: String
        switch item.name {
        case "read": localizedName = String(localized: "readStatus.read")
        case "inProgress": localizedName = String(localized: "readStatus.inProgress")
        case "unread": localizedName = String(localized: "readStatus.unread")
        default: localizedName = item.name
        }
        return ReadingStatsItem(name: localizedName, value: item.value)
      }
      .filter { $0.value > 0 }
  }

  // Index 0 is Sunday on both sides, matching Calendar.current.shortWeekdaySymbols.
  private static func mapWeekdayDistribution(_ counts: [Int]) -> [ReadingStatsItem] {
    Calendar.current.shortWeekdaySymbols.enumerated().map { index, symbol in
      ReadingStatsItem(name: symbol, value: Double(index < counts.count ? counts[index] : 0))
    }
  }

  private static func mapHourlyDistribution(_ counts: [Int]) -> [ReadingStatsItem] {
    (0..<24).map { hour in
      ReadingStatsItem(name: String(format: "%d:00", hour), value: Double(hour < counts.count ? counts[hour] : 0))
    }
  }

  // MARK: - Local Stats

  private static func fetchLocalPayload(instanceId: String, libraryId: String?) async -> ReadingStatsPayload {
    guard let database = await DatabaseOperator.databaseIfConfigured() else {
      return .empty
    }

    async let readBooksTask = database.fetchBooksWithReadProgressForStats(
      instanceId: instanceId,
      libraryId: libraryId
    )
    async let totalBooksTask = database.fetchTotalBooksCount(
      instanceId: instanceId,
      libraryId: libraryId
    )

    let readBooks = await readBooksTask
    let totalBooks = await totalBooksTask

    let completedSeriesIds = Set(
      readBooks
        .lazy
        .filter(\.isCompleted)
        .map { $0.seriesId }
    )
    let readSeries = await database.fetchSeriesByIdsForStats(
      instanceId: instanceId,
      seriesIds: Array(completedSeriesIds)
    )

    return buildPayload(
      filteredBooks: readBooks,
      readSeries: readSeries,
      totalBooks: totalBooks
    )
  }

  // MARK: - Aggregation

  private static func buildPayload(filteredBooks: [Book], readSeries: [Series], totalBooks: Int) -> ReadingStatsPayload
  {
    let booksWithProgress = filteredBooks.filter(\.hasStartedReading)
    let completedBooks = filteredBooks.filter(\.isCompleted)

    let totalPagesRead = completedBooks.reduce(0.0) { partial, book in
      partial + Double(readPageCount(for: book))
    }

    let averagePagesPerBook = completedBooks.isEmpty ? 0 : (totalPagesRead / Double(completedBooks.count)).rounded()
    let readDates = completedBooks.compactMap { $0.readProgress?.readDate }
    let lastReadDate = readDates.max()
    let uniqueReadingDays = Set(readDates.map(Self.dayKey))

    let summary = ReadingStatsSummary(
      totalBooks: Double(totalBooks),
      booksStartedReading: Double(booksWithProgress.count),
      booksCompletedReading: Double(completedBooks.count),
      totalPagesRead: totalPagesRead,
      averagePagesPerBook: averagePagesPerBook,
      readingDays: Double(uniqueReadingDays.count),
      estimatedReadingHours: 0,
      lastReadAt: lastReadDate.map(Self.isoDateTime)
    )

    let statusDistribution = buildStatusDistribution(
      totalBooks: totalBooks,
      filteredBooks: filteredBooks,
      completedBooks: completedBooks
    )

    let dailyDistribution = buildDailyDistribution(completedBooks: completedBooks)
    let hourlyDistribution = buildHourlyDistribution(completedBooks: completedBooks)
    let dailyPagesSeries = buildDailyPagesSeries(completedBooks: completedBooks)

    let dimensions = buildDimensions(completedBooks: completedBooks, readSeries: readSeries)

    return ReadingStatsPayload(
      summary: summary,
      statusDistribution: statusDistribution,
      dailyDistribution: dailyDistribution,
      hourlyDistribution: hourlyDistribution,
      readingTimeSeries: dailyPagesSeries,
      topAuthors: dimensions.topAuthors,
      topGenres: dimensions.topGenres,
      topTags: dimensions.topTags,
      genreDistribution: dimensions.genreDistribution,
      tagDistribution: dimensions.tagDistribution,
      generatedAt: Self.isoDateTime(Date())
    )
  }

  private static func buildStatusDistribution(
    totalBooks: Int,
    filteredBooks: [Book],
    completedBooks: [Book]
  ) -> [ReadingStatsItem] {
    let completedCount = completedBooks.count
    let inProgressCount = filteredBooks.filter(\.isInProgress).count
    let unreadCount = max(totalBooks - filteredBooks.count, 0)

    return [
      ReadingStatsItem(name: String(localized: "readStatus.read"), value: Double(completedCount)),
      ReadingStatsItem(name: String(localized: "readStatus.inProgress"), value: Double(inProgressCount)),
      ReadingStatsItem(name: String(localized: "readStatus.unread"), value: Double(unreadCount)),
    ].filter { $0.value > 0 }
  }

  private static func buildDailyDistribution(completedBooks: [Book]) -> [ReadingStatsItem] {
    let calendar = Calendar.current
    let weekdaySymbols = calendar.shortWeekdaySymbols

    var counts = Array(repeating: 0, count: 7)
    for book in completedBooks {
      guard let readDate = book.readProgress?.readDate else { continue }
      let weekday = calendar.component(.weekday, from: readDate)
      guard weekday >= 1 && weekday <= 7 else { continue }
      counts[weekday - 1] += 1
    }

    return weekdaySymbols.enumerated().map { index, symbol in
      ReadingStatsItem(name: symbol, value: Double(counts[index]))
    }
  }

  private static func buildHourlyDistribution(completedBooks: [Book]) -> [ReadingStatsItem] {
    let calendar = Calendar.current
    var counts = Array(repeating: 0, count: 24)

    for book in completedBooks {
      guard let readDate = book.readProgress?.readDate else { continue }
      let hour = calendar.component(.hour, from: readDate)
      guard hour >= 0 && hour < 24 else { continue }
      counts[hour] += 1
    }

    return counts.enumerated().map { hour, count in
      ReadingStatsItem(name: String(format: "%d:00", hour), value: Double(count))
    }
  }

  private static func buildDailyPagesSeries(completedBooks: [Book]) -> [ReadingStatsTimePoint] {
    guard !completedBooks.isEmpty else { return [] }

    let today = Date()
    let startDate =
      completedBooks
      .compactMap { $0.readProgress?.readDate }
      .min()
      .map { Calendar.current.startOfDay(for: $0) }
      ?? Calendar.current.startOfDay(for: today)

    var pagesByDay: [String: Double] = [:]
    for book in completedBooks {
      guard let progress = book.readProgress else { continue }
      let dayKey = Self.dayKey(progress.readDate)
      let pages = Double(readPageCount(for: book))
      pagesByDay[dayKey, default: 0] += pages
    }

    var points: [ReadingStatsTimePoint] = []
    var cursor = startDate
    let endDate = Calendar.current.startOfDay(for: today)

    while cursor <= endDate {
      let dayKey = Self.dayKey(cursor)
      points.append(
        ReadingStatsTimePoint(
          name: dayKey,
          value: pagesByDay[dayKey, default: 0],
          dateString: dayKey
        )
      )
      guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = nextDay
    }

    return points
  }

  private static func readPageCount(for book: Book) -> Int {
    guard let progress = book.readProgress else { return 0 }

    let mediaPagesCount = max(book.media.pagesCount, 0)
    if progress.completed, mediaPagesCount > 0 {
      return mediaPagesCount
    }

    return max(progress.page, 0)
  }

  private static func buildDimensions(completedBooks: [Book], readSeries: [Series]) -> ReadingStatsDimensions {
    let seriesById = Dictionary(uniqueKeysWithValues: readSeries.map { ($0.id, $0) })
    let booksBySeries = Dictionary(grouping: completedBooks, by: \.seriesId)

    var authorCounts: [String: Int] = [:]
    var genreCounts: [String: Int] = [:]
    var tagCounts: [String: Int] = [:]

    for (seriesId, books) in booksBySeries {
      let series = seriesById[seriesId]

      if let genres = series?.metadata.genres {
        for genre in genres where !genre.isEmpty {
          genreCounts[genre, default: 0] += 1
        }
      }

      var authors = Set<String>()
      var tags = Set<String>()

      if let seriesAuthors = series?.booksMetadata.authors {
        for author in seriesAuthors where !author.name.isEmpty {
          authors.insert(author.name)
        }
      }

      if let seriesTags = series?.metadata.tags {
        for tag in seriesTags where !tag.isEmpty {
          tags.insert(tag)
        }
      }

      for book in books {
        if let bookAuthors = book.metadata.authors {
          for author in bookAuthors where !author.name.isEmpty {
            authors.insert(author.name)
          }
        }

        if let bookTags = book.metadata.tags {
          for tag in bookTags where !tag.isEmpty {
            tags.insert(tag)
          }
        }
      }

      for author in authors {
        authorCounts[author, default: 0] += 1
      }

      for tag in tags {
        tagCounts[tag, default: 0] += 1
      }
    }

    let topAuthors = sortedItems(from: authorCounts)
    let topGenres = sortedItems(from: genreCounts)
    let topTags = sortedItems(from: tagCounts)

    return ReadingStatsDimensions(
      topAuthors: topAuthors,
      topGenres: topGenres,
      topTags: topTags,
      genreDistribution: makeDistribution(from: topGenres),
      tagDistribution: makeDistribution(from: topTags)
    )
  }

  private static func sortedItems(from counts: [String: Int]) -> [ReadingStatsItem] {
    counts
      .map { ReadingStatsItem(name: $0.key, value: Double($0.value)) }
      .sorted {
        if $0.value == $1.value {
          return $0.name.localizedCompare($1.name) == .orderedAscending
        }
        return $0.value > $1.value
      }
  }

  private static func makeDistribution(from items: [ReadingStatsItem], topCount: Int = 17) -> [ReadingStatsItem] {
    guard items.count > topCount else { return items }

    let fixedItems = Array(items.prefix(topCount))
    let otherValue = items.dropFirst(topCount).reduce(0.0) { partial, item in
      partial + item.value
    }

    return fixedItems + [ReadingStatsItem(name: String(localized: "Other"), value: otherValue)]
  }

  private static func normalizeLibraryId(_ libraryId: String?) -> String? {
    guard let libraryId else { return nil }
    let trimmed = libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func dayKey(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func isoDateTime(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

nonisolated private struct ReadingStatsDimensions: Sendable {
  let topAuthors: [ReadingStatsItem]
  let topGenres: [ReadingStatsItem]
  let topTags: [ReadingStatsItem]
  let genreDistribution: [ReadingStatsItem]
  let tagDistribution: [ReadingStatsItem]
}
