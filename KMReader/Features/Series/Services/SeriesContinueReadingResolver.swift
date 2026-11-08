//
// SeriesContinueReadingResolver.swift
//
//

import Foundation

@MainActor
enum SeriesContinueReadingResolver {
  static func resolve(
    seriesId: String,
    instanceId: String,
    isOffline: Bool
  ) async -> Book? {
    if isOffline {
      return await resolveOffline(seriesId: seriesId, instanceId: instanceId)
    }
    return await SeriesContinueReadingOnlineResolver.resolve(seriesId: seriesId)
  }

  /// Resolves from the local projection (all local books, not just downloaded
  /// ones) so callers can present a target before any server round trip.
  static func resolveLocal(
    seriesId: String,
    instanceId: String
  ) async -> Book? {
    guard let database = try? await DatabaseOperator.database() else { return nil }
    return await database.fetchContinueReadingBook(
      seriesId: seriesId, instanceId: instanceId, downloadedOnly: false)
  }

  private static func resolveOffline(seriesId: String, instanceId: String) async -> Book? {
    guard let database = try? await DatabaseOperator.database() else { return nil }
    return await database.fetchContinueReadingBook(
      seriesId: seriesId, instanceId: instanceId, downloadedOnly: true)
  }
}
