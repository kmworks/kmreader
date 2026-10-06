//
// LibraryMetricsLoader.swift
//
//

import Foundation

/// Loads library metrics from the kmrs stats endpoints. Servers without them
/// (Komga, older kmrs) show no metrics: a 404 clears the locally stored
/// numbers, since no source can refresh them there.
struct LibraryMetricsLoader {
  static let shared = LibraryMetricsLoader()

  private let logger = AppLogger(.api)

  func refreshMetrics(instanceId: String) async -> [String: LibraryMetricValues] {
    guard !instanceId.isEmpty else { return [:] }
    guard ServerStatsService.shouldQueryServer(instanceId: instanceId) else { return [:] }

    do {
      let stats = try await ServerStatsService.getLibrariesStats()
      ServerStatsService.recordServerCapability(instanceId: instanceId, supported: true)
      await storeAllLibrariesEntry(instanceId: instanceId, total: stats.total)
      return perLibraryMetrics(from: stats)
    } catch let error as APIError {
      // A transient failure keeps the previously stored numbers.
      guard case .notFound = error else { return [:] }
      ServerStatsService.recordServerCapability(instanceId: instanceId, supported: false)
      await clearStoredMetrics(instanceId: instanceId)
      logger.info("Server stats endpoints unavailable, library metrics hidden")
      return [:]
    } catch {
      return [:]
    }
  }

  private func perLibraryMetrics(
    from stats: ServerLibrariesStatsResponse
  ) -> [String: LibraryMetricValues] {
    stats.libraries.reduce(into: [:]) { result, library in
      result[library.libraryId] = LibraryMetricValues(
        fileSize: library.fileSize,
        seriesCount: library.series,
        booksCount: library.books,
        sidecarsCount: library.sidecars
      )
    }
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
}
