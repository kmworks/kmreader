//
// SeriesDisplayItem.swift
//
//

import Foundation

nonisolated struct SeriesDisplayItem: Equatable, Identifiable, Sendable {
  let id: String
  let instanceId: String
  let series: Series
  let downloadStatus: SeriesDownloadStatus
  let offlinePolicy: OfflinePolicy
  let offlinePolicyLimit: Int
  let collectionIds: [String]

  init(
    instanceId: String,
    series: Series,
    downloadStatus: SeriesDownloadStatus,
    offlinePolicy: OfflinePolicy,
    offlinePolicyLimit: Int,
    collectionIds: [String] = []
  ) {
    id = series.id
    self.instanceId = instanceId
    self.series = series
    self.downloadStatus = downloadStatus
    self.offlinePolicy = offlinePolicy
    self.offlinePolicyLimit = offlinePolicyLimit
    self.collectionIds = collectionIds
  }

  var seriesId: String {
    series.id
  }

  var metaTitle: String {
    series.metadata.title
  }

  var booksCount: Int {
    series.booksCount
  }

  var booksReadCount: Int {
    series.booksReadCount
  }

  var booksUnreadCount: Int {
    series.booksUnreadCount
  }

  var booksInProgressCount: Int {
    series.booksInProgressCount
  }

  var oneshot: Bool {
    series.oneshot
  }

  /// Card text line for oneshots: the primary author's name, so the line
  /// carries useful info instead of just the label; falls back to it.
  var oneshotLine: String {
    series.booksMetadata.authors?.primary?.name ?? String(localized: "Oneshot")
  }

  var navDestination: NavDestination {
    if series.oneshot {
      return NavDestination.oneshotDetail(seriesId: series.id)
    } else {
      return NavDestination.seriesDetail(seriesId: series.id)
    }
  }

  var isUnavailable: Bool {
    series.deleted
  }

  var isUnread: Bool {
    series.isUnread
  }
}
