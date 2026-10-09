//
// KomgaBook.swift
//

import Foundation

nonisolated struct KomgaBook: Codable, Equatable, Sendable {
  var id: String
  var bookId: String
  var seriesId: String
  var libraryId: String
  var instanceId: String
  var name: String
  var url: String
  var number: Double
  var created: Date
  var lastModified: Date
  var sizeBytes: Int64
  var size: String
  var mediaRaw: Data?
  var metadataRaw: Data?
  var readProgressRaw: Data?
  var mediaPagesCount: Int
  var mediaProfile: String?
  var metaTitle: String
  var metaNumber: String
  var metaNumberSort: Double
  var metaReleaseDate: String?
  var progressPage: Int?
  var progressCompleted: Bool?
  var progressReadDate: Date?
  var metaAuthorsIndex: String
  var metaTagsIndex: String
  var isUnavailable: Bool
  var oneshot: Bool
  var seriesTitle: String
  var pagesRaw: Data?
  var tocRaw: Data?
  var webPubManifestRaw: Data?
  var epubProgressionRaw: Data?
  var downloadStatusRaw: String
  var downloadError: String?
  var downloadAt: Date?
  var downloadedSize: Int64
  var readListIdsRaw: Data?
  var soloPagesRaw: Data?
  var epubPreferencesRaw: String?

  init(
    id: String? = nil,
    bookId: String,
    seriesId: String,
    libraryId: String,
    instanceId: String,
    name: String,
    url: String,
    number: Double,
    created: Date,
    lastModified: Date,
    sizeBytes: Int64,
    size: String,
    media: Media,
    metadata: BookMetadata,
    readProgress: ReadProgress?,
    isUnavailable: Bool,
    oneshot: Bool,
    seriesTitle: String = "",
    downloadedSize: Int64 = 0
  ) {
    self.id = id ?? CompositeID.generate(instanceId: instanceId, id: bookId)
    self.bookId = bookId
    self.seriesId = seriesId
    self.libraryId = libraryId
    self.instanceId = instanceId
    self.name = name
    self.url = url
    self.number = number
    self.created = created
    self.lastModified = lastModified
    self.sizeBytes = sizeBytes
    self.size = size
    self.mediaRaw = RawCodableStore.encode(media)
    self.metadataRaw = RawCodableStore.encode(metadata)
    self.readProgressRaw = RawCodableStore.encodeOptional(readProgress)
    self.mediaPagesCount = media.pagesCount
    self.mediaProfile = media.mediaProfile
    self.metaTitle = metadata.title
    self.metaNumber = metadata.number
    self.metaNumberSort = metadata.numberSort
    self.metaReleaseDate = metadata.releaseDate
    self.progressPage = readProgress?.page
    self.progressCompleted = readProgress?.completed
    self.progressReadDate = readProgress?.readDate
    self.metaAuthorsIndex = MetadataIndex.encode(values: metadata.authors?.map(\.name) ?? [])
    self.metaTagsIndex = MetadataIndex.encode(values: metadata.tags ?? [])
    self.isUnavailable = isUnavailable
    self.oneshot = oneshot
    self.seriesTitle = seriesTitle
    self.pagesRaw = nil
    self.tocRaw = nil
    self.webPubManifestRaw = nil
    self.epubProgressionRaw = nil
    self.downloadStatusRaw = "notDownloaded"
    self.downloadError = nil
    self.downloadAt = nil
    self.downloadedSize = downloadedSize
    self.readListIdsRaw = try? JSONEncoder().encode([] as [String])
    self.soloPagesRaw = try? JSONEncoder().encode([] as [Int])
    self.epubPreferencesRaw = nil
  }
}

nonisolated extension KomgaBook {
  static func seriesOfflinePolicySort(_ lhs: KomgaBook, _ rhs: KomgaBook) -> Bool {
    if lhs.metaNumberSort == rhs.metaNumberSort {
      return lhs.bookId < rhs.bookId
    }
    return lhs.metaNumberSort < rhs.metaNumberSort
  }

  var readListIds: [String] {
    get { readListIdsRaw.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
    set { readListIdsRaw = try? JSONEncoder().encode(newValue) }
  }

  var soloPages: [Int] {
    get { soloPagesRaw.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? [] }
    set { soloPagesRaw = try? JSONEncoder().encode(newValue) }
  }

  var epubThemePreferences: EpubThemePreferences? {
    get { epubPreferencesRaw.flatMap { EpubThemePreferences(rawValue: $0) } }
    set { epubPreferencesRaw = newValue?.rawValue }
  }

  var media: Media? {
    get { RawCodableStore.decode(Media.self, from: mediaRaw) }
    set { mediaRaw = RawCodableStore.encodeOptional(newValue) }
  }

  var metadata: BookMetadata? {
    get { RawCodableStore.decode(BookMetadata.self, from: metadataRaw) }
    set { metadataRaw = RawCodableStore.encodeOptional(newValue) }
  }

  var readProgress: ReadProgress? {
    get { RawCodableStore.decode(ReadProgress.self, from: readProgressRaw) }
    set { readProgressRaw = RawCodableStore.encodeOptional(newValue) }
  }

  /// Computed property for download status.
  var downloadStatus: DownloadStatus {
    get {
      switch downloadStatusRaw {
      case "pending":
        return .pending
      case "downloaded":
        return .downloaded
      case "failed":
        return .failed(error: downloadError ?? "Unknown error")
      default:
        return .notDownloaded
      }
    }
    set {
      switch newValue {
      case .notDownloaded:
        downloadStatusRaw = "notDownloaded"
        downloadError = nil
        downloadAt = nil
      case .pending:
        downloadStatusRaw = "pending"
        downloadError = nil
      case .downloaded:
        downloadStatusRaw = "downloaded"
        downloadError = nil
      case .failed(let error):
        downloadStatusRaw = "failed"
        downloadError = error
      }
    }
  }

  var downloadContentKind: DownloadContentKind {
    if let archiveFormat = downloadedImageArchiveFormat {
      return .archiveImages(archiveFormat)
    }

    switch mediaProfile.flatMap(MediaProfile.init(rawValue:)) ?? .unknown {
    case .pdf:
      return .pdf
    case .epub:
      let isDivinaCompatible = media?.epubDivinaCompatible ?? false
      return isDivinaCompatible ? .epubDivina : .epubWebPub
    case .divina, .unknown:
      return .pages
    }
  }

  private var downloadedImageArchiveFormat: DownloadedImageArchiveFormat? {
    if let urlExtension = URL(string: url)?.pathExtension.lowercased(),
      let archiveFormat = DownloadedImageArchiveFormat(fileExtension: urlExtension)
    {
      return archiveFormat
    }

    let mediaType = media?.mediaType
      .split(separator: ";")
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    switch mediaType {
    case "application/vnd.comicbook+zip", "application/x-cbz", "application/zip":
      return .cbz
    case "application/vnd.comicbook-rar", "application/x-cbr", "application/vnd.rar",
      "application/x-rar-compressed":
      return .cbr
    default:
      return nil
    }
  }

  var hasStartedReading: Bool {
    readProgress != nil
  }

  var isUnread: Bool {
    !hasStartedReading
  }

  var isCompleted: Bool {
    progressCompleted == true
  }

  var isInProgress: Bool {
    hasStartedReading && !isCompleted
  }

  mutating func updateMedia(_ media: Media, raw: Data?) {
    mediaRaw = raw ?? RawCodableStore.encode(media)
    syncMediaFields(media)
  }

  mutating func updateMetadata(_ metadata: BookMetadata, raw: Data?) {
    metadataRaw = raw ?? RawCodableStore.encode(metadata)
    syncMetadataFields(metadata)
  }

  mutating func applyContent(media: Media, metadata: BookMetadata, readProgress: ReadProgress?) {
    updateMedia(media, raw: RawCodableStore.encode(media))
    updateMetadata(metadata, raw: RawCodableStore.encode(metadata))
    updateReadProgress(readProgress, raw: RawCodableStore.encodeOptional(readProgress))
  }

  mutating func updateReadProgress(_ readProgress: ReadProgress?) {
    updateReadProgress(readProgress, raw: RawCodableStore.encodeOptional(readProgress))
  }

  mutating func updateReadProgress(_ readProgress: ReadProgress?, raw: Data?) {
    readProgressRaw = raw
    syncReadProgressFields(readProgress)
  }

  private mutating func syncMediaFields(_ media: Media) {
    mediaPagesCount = media.pagesCount
    mediaProfile = media.mediaProfile
  }

  private mutating func syncMetadataFields(_ metadata: BookMetadata) {
    metaTitle = metadata.title
    metaNumber = metadata.number
    metaNumberSort = metadata.numberSort
    metaReleaseDate = metadata.releaseDate
    metaAuthorsIndex = MetadataIndex.encode(values: metadata.authors?.map(\.name) ?? [])
    metaTagsIndex = MetadataIndex.encode(values: metadata.tags ?? [])

  }

  private mutating func syncReadProgressFields(_ readProgress: ReadProgress?) {
    progressPage = readProgress?.page
    progressCompleted = readProgress?.completed
    progressReadDate = readProgress?.readDate
  }

  func toBook() -> Book {
    let media = media ?? Media.empty
    let metadata = metadata ?? BookMetadata.empty

    return Book(
      id: bookId,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      libraryId: libraryId,
      name: name,
      url: url,
      number: number,
      created: created,
      lastModified: lastModified,
      sizeBytes: sizeBytes,
      size: size,
      media: media,
      metadata: metadata,
      readProgress: readProgress,
      deleted: isUnavailable,
      fileHash: nil,
      oneshot: oneshot
    )
  }

  var pages: [BookPage]? {
    get {
      pagesRaw.flatMap { try? JSONDecoder().decode([BookPage].self, from: $0) }
    }
    set {
      pagesRaw = try? JSONEncoder().encode(newValue)
    }
  }

  var tableOfContents: [ReaderTOCEntry]? {
    get {
      tocRaw.flatMap { try? JSONDecoder().decode([ReaderTOCEntry].self, from: $0) }
    }
    set {
      tocRaw = try? JSONEncoder().encode(newValue)
    }
  }
}
