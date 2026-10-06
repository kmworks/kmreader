//
// ServerLibrariesStatsResponse.swift
//
//

import Foundation

/// `GET /api/v1/stats/libraries` (kmrs-private): per-library content counts
/// plus their total, scoped to the caller's visibility. Sidecar counts carry
/// no visibility of their own, so the server only sends them to admins.
nonisolated struct ServerLibrariesStatsResponse: Decodable, Sendable {
  let libraries: [LibraryStats]
  let total: LibraryStatsTotal

  struct LibraryStats: Decodable, Sendable {
    let libraryId: String
    let name: String
    let series: Double
    let books: Double
    let fileSize: Double
    let readlists: Double
    let collections: Double
    let sidecars: Double?
  }

  struct LibraryStatsTotal: Decodable, Sendable {
    let series: Double
    let books: Double
    let fileSize: Double
    let readlists: Double
    let collections: Double
    let sidecars: Double?
  }
}
