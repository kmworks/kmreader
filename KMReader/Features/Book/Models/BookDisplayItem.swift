//
// BookDisplayItem.swift
//
//

import Foundation

nonisolated struct BookDisplayItem: Equatable, Identifiable, Sendable {
  let id: String
  let instanceId: String
  let book: Book
  let downloadStatus: DownloadStatus
  let readListIds: [String]
  let protectionSources: [OfflineProtectionSource]

  init(
    instanceId: String,
    book: Book,
    downloadStatus: DownloadStatus,
    readListIds: [String] = [],
    protectionSources: [OfflineProtectionSource] = []
  ) {
    id = book.id
    self.instanceId = instanceId
    self.book = book
    self.downloadStatus = downloadStatus
    self.readListIds = readListIds
    self.protectionSources = protectionSources
  }

  var bookId: String {
    book.id
  }

  var seriesId: String {
    book.seriesId
  }

  var seriesTitle: String {
    book.seriesTitle
  }

  var created: Date {
    book.created
  }

  var size: String {
    book.size
  }

  var media: Media {
    book.media
  }

  var mediaPagesCount: Int {
    book.media.pagesCount
  }

  var metaTitle: String {
    book.metadata.title
  }

  var metaNumber: String {
    book.metadata.number
  }

  var metaReleaseDate: String? {
    book.metadata.releaseDate
  }

  var progressPage: Int? {
    book.readProgress?.page
  }

  var progressCompleted: Bool? {
    book.readProgress?.completed
  }

  var completedLastReadText: String? {
    guard isCompleted, let readDate = book.readProgress?.readDate else { return nil }
    return readDate.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
  }

  var bookTitleLine: String {
    if book.oneshot {
      return book.metadata.title
    }
    return String("\(book.metadata.number) - \(book.metadata.title)")
  }

  var progress: Double {
    guard let progressPage = book.readProgress?.page else { return 0 }
    guard book.media.pagesCount > 0 else { return 0 }
    return Double(progressPage) / Double(book.media.pagesCount)
  }

  var completedMetaText: String {
    completedLastReadText ?? "\(book.media.pagesCount) pages"
  }

  var oneshot: Bool {
    book.oneshot
  }

  /// Card text line for oneshots: the primary author's name, so the line
  /// carries useful info instead of just the label; falls back to it.
  var oneshotLine: String {
    book.metadata.authors?.primary?.name ?? String(localized: "Oneshot")
  }

  var isUnavailable: Bool {
    book.deleted
  }

  var isUnread: Bool {
    book.isUnread
  }

  var isCompleted: Bool {
    book.isCompleted
  }

  var isInProgress: Bool {
    book.isInProgress
  }
}
