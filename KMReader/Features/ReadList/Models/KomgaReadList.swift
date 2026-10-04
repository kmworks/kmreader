//
// KomgaReadList.swift
//

import Foundation

nonisolated struct KomgaReadList: Codable, Equatable, Sendable {
  var id: String
  var readListId: String
  var instanceId: String
  var name: String
  var summary: String
  var ordered: Bool
  var createdDate: Date
  var lastModifiedDate: Date
  var filtered: Bool
  var isPinned: Bool
  var bookIdsRaw: Data?
  var downloadStatusRaw: String
  var downloadError: String?
  var downloadAt: Date?
  var downloadedSize: Int64
  var downloadedBooks: Int
  var pendingBooks: Int
  var offlinePolicyRaw: String
  var offlinePolicyLimit: Int

  init(
    id: String? = nil,
    readListId: String,
    instanceId: String,
    name: String,
    summary: String,
    ordered: Bool,
    createdDate: Date,
    lastModifiedDate: Date,
    filtered: Bool,
    isPinned: Bool = false,
    bookIds: [String] = [],
    downloadedBooks: Int = 0,
    pendingBooks: Int = 0,
    downloadedSize: Int64 = 0,
    offlinePolicy: OfflinePolicy = .manual,
    offlinePolicyLimit: Int = 0
  ) {
    self.id = id ?? CompositeID.generate(instanceId: instanceId, id: readListId)
    self.readListId = readListId
    self.instanceId = instanceId
    self.name = name
    self.summary = summary
    self.ordered = ordered
    self.createdDate = createdDate
    self.lastModifiedDate = lastModifiedDate
    self.filtered = filtered
    self.isPinned = isPinned
    self.bookIdsRaw = try? JSONEncoder().encode(bookIds)
    self.downloadStatusRaw = "notDownloaded"
    self.downloadError = nil
    self.downloadAt = nil
    self.downloadedSize = downloadedSize
    self.downloadedBooks = downloadedBooks
    self.pendingBooks = pendingBooks
    self.offlinePolicyRaw = offlinePolicy.storageValue
    self.offlinePolicyLimit = max(0, offlinePolicyLimit)
  }
}

nonisolated extension KomgaReadList {
  var bookIds: [String] {
    get { bookIdsRaw.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
    set { bookIdsRaw = try? JSONEncoder().encode(newValue) }
  }

  var offlinePolicy: OfflinePolicy {
    get {
      OfflinePolicy(storageValue: offlinePolicyRaw)
    }
    set {
      offlinePolicyRaw = newValue.storageValue
    }
  }

  /// Computed property for download status.
  var downloadStatus: SeriesDownloadStatus {
    let downloaded = downloadedBooks
    let pending = pendingBooks
    let total = bookIds.count

    if downloadStatusRaw == "downloaded" || (downloaded == total && total > 0) {
      return .downloaded
    }

    if pending > 0 {
      return .pending(downloaded: downloaded, pending: pending, total: total)
    }

    if downloadStatusRaw == "failed" {
      return .failed
    }

    if downloaded > 0 {
      return .partiallyDownloaded(downloaded: downloaded, total: total)
    }

    return .notDownloaded
  }

  func toReadList() -> ReadList {
    ReadList(
      id: readListId,
      name: name,
      summary: summary,
      ordered: ordered,
      bookIds: bookIds,
      createdDate: createdDate,
      lastModifiedDate: lastModifiedDate,
      filtered: filtered
    )
  }
}
