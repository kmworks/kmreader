//
// KomgaSeries.swift
//

import Foundation

nonisolated struct KomgaSeries: Codable, Equatable, Sendable {
  var id: String
  var seriesId: String
  var libraryId: String
  var instanceId: String
  var name: String
  var url: String
  var created: Date
  var lastModified: Date
  var booksCount: Int
  var booksReadCount: Int
  var booksUnreadCount: Int
  var booksInProgressCount: Int
  var metadataRaw: Data?
  var booksMetadataRaw: Data?
  var metaTitle: String
  var metaTitleSort: String
  var metaPublisherIndex: String
  var metaAuthorsIndex: String
  var metaGenresIndex: String
  var metaTagsIndex: String
  var metaLanguageIndex: String
  var isUnavailable: Bool
  var oneshot: Bool
  var downloadStatusRaw: String
  var downloadError: String?
  var downloadAt: Date?
  var downloadedSize: Int64
  var downloadedBooks: Int
  var pendingBooks: Int
  var offlinePolicyRaw: String
  var offlinePolicyLimit: Int
  var collectionIdsRaw: Data?

  init(
    id: String? = nil,
    seriesId: String,
    libraryId: String,
    instanceId: String,
    name: String,
    url: String,
    created: Date,
    lastModified: Date,
    booksCount: Int,
    booksReadCount: Int,
    booksUnreadCount: Int,
    booksInProgressCount: Int,
    metadata: SeriesMetadata,
    booksMetadata: SeriesBooksMetadata,
    isUnavailable: Bool,
    oneshot: Bool,
    downloadedBooks: Int = 0,
    pendingBooks: Int = 0,
    downloadedSize: Int64 = 0,
    offlinePolicy: OfflinePolicy = .manual,
    offlinePolicyLimit: Int = 0
  ) {
    self.id = id ?? CompositeID.generate(instanceId: instanceId, id: seriesId)
    self.seriesId = seriesId
    self.libraryId = libraryId
    self.instanceId = instanceId
    self.name = name
    self.url = url
    self.created = created
    self.lastModified = lastModified
    self.booksCount = booksCount
    self.booksReadCount = booksReadCount
    self.booksUnreadCount = booksUnreadCount
    self.booksInProgressCount = booksInProgressCount
    self.metadataRaw = RawCodableStore.encode(metadata)
    self.booksMetadataRaw = RawCodableStore.encode(booksMetadata)
    self.metaTitle = metadata.title
    self.metaTitleSort = metadata.titleSort
    self.metaPublisherIndex = MetadataIndex.encode(value: metadata.publisher)
    self.metaAuthorsIndex = MetadataIndex.encode(values: booksMetadata.authors?.map(\.name) ?? [])
    self.metaGenresIndex = MetadataIndex.encode(values: metadata.genres ?? [])
    self.metaTagsIndex = MetadataIndex.encode(values: metadata.tags ?? [])
    self.metaLanguageIndex = MetadataIndex.encode(value: metadata.language)
    self.isUnavailable = isUnavailable
    self.oneshot = oneshot
    self.downloadStatusRaw = "notDownloaded"
    self.downloadError = nil
    self.downloadAt = nil
    self.downloadedSize = downloadedSize
    self.downloadedBooks = downloadedBooks
    self.pendingBooks = pendingBooks
    self.offlinePolicyRaw = offlinePolicy.storageValue
    self.offlinePolicyLimit = max(0, offlinePolicyLimit)
    self.collectionIdsRaw = try? JSONEncoder().encode([] as [String])
  }
}

nonisolated extension KomgaSeries {
  var collectionIds: [String] {
    get {
      collectionIdsRaw.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }
    set { collectionIdsRaw = try? JSONEncoder().encode(newValue) }
  }

  var metadata: SeriesMetadata? {
    get { RawCodableStore.decode(SeriesMetadata.self, from: metadataRaw) }
    set { metadataRaw = RawCodableStore.encodeOptional(newValue) }
  }

  var booksMetadata: SeriesBooksMetadata? {
    get { RawCodableStore.decode(SeriesBooksMetadata.self, from: booksMetadataRaw) }
    set { booksMetadataRaw = RawCodableStore.encodeOptional(newValue) }
  }

  /// Computed property for download status.
  var downloadStatus: SeriesDownloadStatus {
    let raw = downloadStatusRaw
    let downloaded = downloadedBooks
    let pending = pendingBooks
    let total = booksCount

    if raw == "downloaded" || downloaded == total {
      return .downloaded
    }

    if pending > 0 {
      return .pending(downloaded: downloaded, pending: pending, total: total)
    }

    if raw == "failed" {
      return .failed
    }

    if downloaded > 0 {
      return .partiallyDownloaded(downloaded: downloaded, total: total)
    }

    return .notDownloaded
  }

  var hasStartedReading: Bool {
    booksReadCount > 0 || booksInProgressCount > 0
  }

  var isUnread: Bool {
    !hasStartedReading
  }

  var readStatus: ReadStatus {
    ReadStatus.fromSeriesCounts(
      booksCount: booksCount,
      booksReadCount: booksReadCount,
      booksInProgressCount: booksInProgressCount
    )
  }

  /// Computed property for offline policy.
  var offlinePolicy: OfflinePolicy {
    get {
      OfflinePolicy(storageValue: offlinePolicyRaw)
    }
    set {
      offlinePolicyRaw = newValue.storageValue
    }
  }

  mutating func updateMetadata(_ metadata: SeriesMetadata, raw: Data?) {
    metadataRaw = raw ?? RawCodableStore.encode(metadata)
    syncMetadataFields(metadata)
  }

  mutating func updateBooksMetadata(_ booksMetadata: SeriesBooksMetadata, raw: Data?) {
    booksMetadataRaw = raw ?? RawCodableStore.encode(booksMetadata)
    syncBooksMetadataFields(booksMetadata)
  }

  mutating func applyContent(metadata: SeriesMetadata, booksMetadata: SeriesBooksMetadata) {
    updateMetadata(metadata, raw: RawCodableStore.encode(metadata))
    updateBooksMetadata(booksMetadata, raw: RawCodableStore.encode(booksMetadata))
  }

  private mutating func syncMetadataFields(_ metadata: SeriesMetadata) {
    metaTitle = metadata.title
    metaTitleSort = metadata.titleSort

    metaPublisherIndex = MetadataIndex.encode(value: metadata.publisher)
    metaGenresIndex = MetadataIndex.encode(values: metadata.genres ?? [])
    metaTagsIndex = MetadataIndex.encode(values: metadata.tags ?? [])
    metaLanguageIndex = MetadataIndex.encode(value: metadata.language)
  }

  private mutating func syncBooksMetadataFields(_ booksMetadata: SeriesBooksMetadata) {
    metaAuthorsIndex = MetadataIndex.encode(values: booksMetadata.authors?.map(\.name) ?? [])
  }

  func toSeries() -> Series {
    let metadata = metadata ?? SeriesMetadata.empty
    let booksMetadata = booksMetadata ?? SeriesBooksMetadata.empty

    return Series(
      id: seriesId,
      libraryId: libraryId,
      name: name,
      url: url,
      created: created,
      lastModified: lastModified,
      booksCount: booksCount,
      booksReadCount: booksReadCount,
      booksUnreadCount: booksUnreadCount,
      booksInProgressCount: booksInProgressCount,
      metadata: metadata,
      booksMetadata: booksMetadata,
      deleted: isUnavailable,
      oneshot: oneshot
    )
  }
}
