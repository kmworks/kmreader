//
// PendingDownloadDeletion.swift
//
//

import Foundation

/// A deletion staged behind an undo toast: the books stay fully intact until the
/// toast settles, so an undo only has to drop this record.
struct PendingDownloadDeletion: Sendable {
  enum CommitKind: Sendable {
    /// Protection sources go manual first so nothing re-downloads the books.
    case manualBooks
    case allDownloaded
    case readBooks
    /// Queue tasks (pending/failed downloads), not downloaded copies.
    case cancelDownload
    /// A single downloaded book toggled off; plain delete, no protection flip.
    case singleBook
    case seriesAll(seriesId: String)
    case seriesRead(seriesId: String)
    case readListAll(readListId: String)
    case readListRead(readListId: String)
  }

  let id: UUID
  /// Assigned after the toast is enqueued; a record without it has no toast to
  /// cancel and is dropped directly.
  var notificationId: UUID?
  let instanceId: String
  let seriesIds: Set<String>
  let bookIds: [String]
  let kind: CommitKind
}
