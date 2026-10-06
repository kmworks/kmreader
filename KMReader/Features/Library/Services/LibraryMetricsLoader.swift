//
// LibraryMetricsLoader.swift
//
//

import Foundation

/// Loads library metrics from the kmrs stats endpoints, falling back to the
/// actuator metrics (library size/series/books only) on servers without them
/// (Komga, older kmrs). Numbers are cleared only when both sources are dead,
/// since nothing can refresh them there.
struct LibraryMetricsLoader {
  static let shared = LibraryMetricsLoader()

  private let logger = AppLogger(.api)

  func refreshMetrics(instanceId: String) async -> [String: LibraryMetricValues] {
    guard !instanceId.isEmpty, !AppConfig.isOffline else { return [:] }

    if ServerStatsService.shouldQueryServer(instanceId: instanceId) {
      do {
        let stats = try await ServerStatsService.getLibrariesStats()
        ServerStatsService.recordServerCapability(instanceId: instanceId, supported: true)
        await storeAllLibrariesEntry(instanceId: instanceId, total: stats.total)
        return perLibraryMetrics(from: stats)
      } catch let error as APIError {
        // A transient failure keeps the previously stored numbers.
        guard case .notFound = error else { return [:] }
        ServerStatsService.recordServerCapability(instanceId: instanceId, supported: false)
      } catch {
        return [:]
      }
    }

    return await actuatorFallbackMetrics(instanceId: instanceId)
  }

  private func perLibraryMetrics(
    from stats: ServerLibrariesStatsResponse
  ) -> [String: LibraryMetricValues] {
    stats.libraries.reduce(into: [:]) { result, library in
      result[library.libraryId] = LibraryMetricValues(
        fileSize: library.fileSize,
        seriesCount: library.series,
        booksCount: library.books,
        sidecarsCount: library.sidecars,
        collectionsCount: library.collections,
        readlistsCount: library.readlists
      )
    }
  }

  private func actuatorFallbackMetrics(instanceId: String) async -> [String: LibraryMetricValues] {
    do {
      async let fileSize = actuatorMetric(.booksFileSize)
      async let series = actuatorMetric(.series)
      async let books = actuatorMetric(.books)

      let sizes = try await fileSize
      let seriesCounts = try await series
      let bookCounts = try await books

      var perLibrary: [String: LibraryMetricValues] = [:]
      for (libraryId, value) in sizes.values {
        perLibrary[libraryId, default: LibraryMetricValues()].fileSize = value
      }
      for (libraryId, value) in seriesCounts.values {
        perLibrary[libraryId, default: LibraryMetricValues()].seriesCount = value
      }
      for (libraryId, value) in bookCounts.values {
        perLibrary[libraryId, default: LibraryMetricValues()].booksCount = value
      }

      // An emptied library vanishes from the actuator tags; zero-fill it from
      // the known libraries so its stale numbers do not linger.
      let knownIds = await knownLibraryIds(instanceId: instanceId)
      if sizes.total != nil {
        for libraryId in knownIds where perLibrary[libraryId]?.fileSize == nil {
          perLibrary[libraryId, default: LibraryMetricValues()].fileSize = 0
        }
      }
      if seriesCounts.total != nil {
        for libraryId in knownIds where perLibrary[libraryId]?.seriesCount == nil {
          perLibrary[libraryId, default: LibraryMetricValues()].seriesCount = 0
        }
      }
      if bookCounts.total != nil {
        for libraryId in knownIds where perLibrary[libraryId]?.booksCount == nil {
          perLibrary[libraryId, default: LibraryMetricValues()].booksCount = 0
        }
      }

      let total = LibraryMetricValues(
        fileSize: sizes.total, seriesCount: seriesCounts.total, booksCount: bookCounts.total)

      guard total.hasAnyValue || !perLibrary.isEmpty else {
        await clearStoredMetrics(instanceId: instanceId)
        logger.info("No library metrics source available, library metrics hidden")
        return [:]
      }

      await storeAllLibrariesEntry(instanceId: instanceId, total: total)
      return perLibrary
    } catch {
      // A transient actuator failure keeps the previously stored numbers.
      return [:]
    }
  }

  /// One actuator metric: the untagged total plus each library's tagged value.
  /// A 404 means the metric is genuinely absent (empty result); any other
  /// error is transient and propagates.
  private func actuatorMetric(_ name: MetricName) async throws -> (total: Double?, values: [String: Double]) {
    let metric: Metric
    do {
      metric = try await ManagementService.getMetric(name.rawValue)
    } catch let error as APIError {
      guard case .notFound = error else { throw error }
      return (nil, [:])
    }
    let total = metric.measurements.first(where: { $0.statistic == "VALUE" })?.value
    guard let libraryTag = metric.availableTags?.first(where: { $0.tag == "library" }) else {
      return (total, [:])
    }
    var values: [String: Double] = [:]
    await withTaskGroup(of: (String, Double?).self) { group in
      for libraryId in libraryTag.values {
        group.addTask {
          let libraryMetric = try? await ManagementService.getMetric(
            name.rawValue, tags: [MetricTag(key: "library", value: libraryId)])
          let value = libraryMetric?.measurements.first(where: { $0.statistic == "VALUE" })?.value
          return (libraryId, value)
        }
      }
      for await (libraryId, value) in group {
        values[libraryId] = value
      }
    }
    return (total, values)
  }

  private func knownLibraryIds(instanceId: String) async -> [String] {
    let database = try? await DatabaseOperator.database()
    return (try? await database?.fetchSidebarLibraries(instanceId: instanceId).map(\.libraryId)) ?? []
  }

  private func storeAllLibrariesEntry(
    instanceId: String,
    total: ServerLibrariesStatsResponse.LibraryStatsTotal
  ) async {
    let database = try? await DatabaseOperator.database()
    try? await database?.upsertAllLibrariesEntry(
      instanceId: instanceId,
      fileSize: total.fileSize,
      booksCount: total.books,
      seriesCount: total.series,
      sidecarsCount: total.sidecars,
      collectionsCount: total.collections,
      readlistsCount: total.readlists
    )
  }

  private func storeAllLibrariesEntry(instanceId: String, total: LibraryMetricValues) async {
    let database = try? await DatabaseOperator.database()
    try? await database?.upsertAllLibrariesEntry(
      instanceId: instanceId,
      fileSize: total.fileSize,
      booksCount: total.booksCount,
      seriesCount: total.seriesCount,
      sidecarsCount: total.sidecarsCount,
      collectionsCount: nil,
      readlistsCount: nil
    )
  }

  private func clearStoredMetrics(instanceId: String) async {
    let database = try? await DatabaseOperator.database()
    try? await database?.clearLibraryMetrics(instanceId: instanceId)
  }
}

nonisolated struct LibraryMetricValues: Equatable, Sendable {
  var fileSize: Double?
  var seriesCount: Double?
  var booksCount: Double?
  var sidecarsCount: Double?
  var collectionsCount: Double?
  var readlistsCount: Double?

  var hasAnyValue: Bool {
    fileSize != nil || seriesCount != nil || booksCount != nil || sidecarsCount != nil
      || collectionsCount != nil || readlistsCount != nil
  }
}
