//
// ReadingStatsViewModel.swift
//
//

import Foundation

@MainActor
@Observable
final class ReadingStatsViewModel {
  var payload: ReadingStatsPayload?
  var dataSource: ReadingStatsDataSource = .local
  var lastUpdatedAt: Date?
  var selectedTimeRange: ReadingStatsTimeRange = .last6Months
  var isLoading = false
  var isRefreshing = false
  var errorMessage: String?

  // Cached stats are immediately displayed; if last refresh is older than this interval, refresh in background.
  private let autoRefreshInterval: TimeInterval = 24 * 60 * 60
  private let cacheStore = ReadingStatsCacheStore.shared

  func load(instanceId: String, libraryId: String, forceRefresh: Bool = false) async {
    guard !instanceId.isEmpty else {
      payload = nil
      dataSource = .local
      lastUpdatedAt = nil
      errorMessage = nil
      return
    }

    let cachedSnapshot = cacheStore.snapshot(instanceId: instanceId, libraryId: libraryId)

    if let cachedSnapshot {
      apply(snapshot: cachedSnapshot)

      let cacheAge = Date().timeIntervalSince(cachedSnapshot.cachedAt)
      if forceRefresh == false && cacheAge <= autoRefreshInterval {
        return
      }
    }

    errorMessage = nil
    if payload == nil {
      isLoading = true
    } else {
      isRefreshing = true
    }

    do {
      let fetched = try await ReadingStatsService.fetchReadingStats(
        libraryId: normalizedLibraryId(libraryId)
      )
      let snapshot = ReadingStatsSnapshot(
        libraryId: normalizedLibraryId(libraryId),
        cachedAt: Date(),
        payload: fetched.payload,
        dataSource: fetched.dataSource
      )
      cacheStore.upsert(snapshot: snapshot, instanceId: instanceId, libraryId: libraryId)
      apply(snapshot: snapshot)
    } catch {
      if let cachedSnapshot {
        apply(snapshot: cachedSnapshot)
        errorMessage = String(localized: "Failed to refresh reading stats. Showing cached data.")
      } else {
        payload = nil
        lastUpdatedAt = nil
        errorMessage = error.localizedDescription
        ErrorManager.shared.alert(error: error)
      }
    }

    isLoading = false
    isRefreshing = false
  }

  func readingPagesHeatmapWeeks(referenceDate: Date = Date()) -> [ReadingPagesHeatmapWeek] {
    let dailyPoints = makeDailyPagePoints()
    guard !dailyPoints.isEmpty else {
      return []
    }

    let now = Self.utcCalendar.startOfDay(for: referenceDate)
    let earliestDate = dailyPoints.map(\.date).min() ?? now
    let window = makeHeatmapWindow(referenceDate: now, earliestDate: earliestDate)
    guard window.startDate <= window.endDate else {
      return []
    }

    var pagesByKey: [String: Double] = [:]
    for point in dailyPoints {
      guard point.date >= window.startDate && point.date <= window.endDate else { continue }
      let key = Self.dayKey(for: point.date)
      pagesByKey[key, default: 0] += point.pages
    }

    var points: [ReadingStatsTimePoint] = []
    var cursor = window.startDate

    while cursor <= window.endDate {
      let key = Self.dayKey(for: cursor)
      let value = pagesByKey[key, default: 0]

      points.append(
        ReadingStatsTimePoint(
          name: Self.dayAxisLabel(for: key),
          value: (value * 100).rounded() / 100,
          dateString: key
        )
      )

      guard let nextCursor = Self.utcCalendar.date(byAdding: .day, value: 1, to: cursor) else {
        break
      }
      cursor = nextCursor
    }

    return Self.makeHeatmapWeeks(points: points)
  }

  private func makeDailyPagePoints() -> [(date: Date, pages: Double)] {
    guard let readingTimeSeries = payload?.readingTimeSeries, !readingTimeSeries.isEmpty else {
      return []
    }

    return readingTimeSeries.compactMap { point -> (date: Date, pages: Double)? in
      guard let parsedDate = Self.parseDate(point.dateString ?? point.name) else {
        return nil
      }
      return (Self.utcCalendar.startOfDay(for: parsedDate), point.value)
    }
  }

  private func makeHeatmapWindow(referenceDate: Date, earliestDate: Date) -> ReadingTimeWindow {
    let now = Self.utcCalendar.startOfDay(for: referenceDate)
    let weekday = Self.utcCalendar.component(.weekday, from: now)

    let startDate: Date
    switch selectedTimeRange {
    case .thisWeek:
      let offset = weekday - 1
      startDate = Self.utcCalendar.date(byAdding: .day, value: -offset, to: now) ?? now
    case .last7Days:
      startDate = Self.utcCalendar.date(byAdding: .day, value: -6, to: now) ?? now
    case .last30Days:
      startDate = Self.utcCalendar.date(byAdding: .day, value: -29, to: now) ?? now
    case .last90Days:
      startDate = Self.utcCalendar.date(byAdding: .day, value: -89, to: now) ?? now
    case .last6Months:
      startDate = Self.utcCalendar.date(byAdding: .month, value: -6, to: now) ?? now
    case .lastYear:
      startDate = Self.utcCalendar.date(byAdding: .year, value: -1, to: now) ?? now
    case .allTime:
      startDate = earliestDate
    }

    return ReadingTimeWindow(
      startDate: Self.utcCalendar.startOfDay(for: startDate),
      endDate: now
    )
  }

  private static func makeHeatmapWeeks(points: [ReadingStatsTimePoint]) -> [ReadingPagesHeatmapWeek] {
    let datedPoints = points.compactMap { point -> (date: Date, point: ReadingStatsTimePoint)? in
      guard let parsedDate = parseDate(point.dateString ?? point.name) else {
        return nil
      }
      return (utcCalendar.startOfDay(for: parsedDate), point)
    }
    .sorted { $0.date < $1.date }

    guard !datedPoints.isEmpty else {
      return []
    }

    var weeks: [ReadingPagesHeatmapWeek] = []
    var currentWeekStart: Date?
    var currentDays = [ReadingStatsTimePoint?](repeating: nil, count: 7)

    for datedPoint in datedPoints {
      let weekdayIndex = max(0, min(utcCalendar.component(.weekday, from: datedPoint.date) - 1, 6))
      let weekStart =
        utcCalendar.date(byAdding: .day, value: -weekdayIndex, to: datedPoint.date)
        ?? datedPoint.date

      if let currentWeekStart, currentWeekStart != weekStart {
        weeks.append(
          ReadingPagesHeatmapWeek(
            id: dayKey(for: currentWeekStart),
            days: currentDays
          )
        )
        currentDays = [ReadingStatsTimePoint?](repeating: nil, count: 7)
      }

      currentWeekStart = weekStart
      currentDays[weekdayIndex] = datedPoint.point
    }

    if let currentWeekStart {
      weeks.append(
        ReadingPagesHeatmapWeek(
          id: dayKey(for: currentWeekStart),
          days: currentDays
        )
      )
    }

    return weeks
  }

  private struct ReadingTimeWindow {
    let startDate: Date
    let endDate: Date
  }

  private static func dayKey(for date: Date) -> String {
    dayKeyFormatter.string(from: date)
  }

  private static func dayAxisLabel(for key: String) -> String {
    guard let date = dayKeyFormatter.date(from: key) else { return key }
    return dayAxisLabelFormatter.string(from: date)
  }

  static func parseDate(_ rawValue: String?) -> Date? {
    guard let rawValue else { return nil }

    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let date = iso8601WithFractional.date(from: trimmed) {
      return date
    }
    if let date = iso8601.date(from: trimmed) {
      return date
    }

    for formatter in additionalDateFormatters {
      if let date = formatter.date(from: trimmed) {
        return date
      }
    }

    return nil
  }

  private func apply(snapshot: ReadingStatsSnapshot) {
    payload = snapshot.payload
    dataSource = snapshot.dataSource
    lastUpdatedAt = snapshot.cachedAt
  }

  private func normalizedLibraryId(_ libraryId: String) -> String {
    libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let iso8601WithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let additionalDateFormatters: [DateFormatter] = {
    // Bare date strings are UTC day keys: the server time series uses UTC days
    // and the local aggregation's dayKey is UTC-formatted as well.
    let utcFormats = [
      "yyyy-MM-dd",
      "yyyy-MM",
      "yyyy",
    ]
    let localFormats = [
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd'T'HH:mm:ss",
      "yyyy-MM-dd'T'HH:mm:ss.SSS",
    ]

    func makeFormatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = timeZone
      formatter.dateFormat = format
      return formatter
    }

    return utcFormats.map { makeFormatter($0, TimeZone(secondsFromGMT: 0) ?? .gmt) }
      + localFormats.map { makeFormatter($0, .current) }
  }()

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }()

  private static let dayKeyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let dayAxisLabelFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()
}
