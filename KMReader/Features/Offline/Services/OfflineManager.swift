//
// OfflineManager.swift
//
//

import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

#if os(iOS)
  import UIKit
#endif

#if os(iOS)
  private typealias BackgroundTaskID = UIBackgroundTaskIdentifier
#else
  private typealias BackgroundTaskID = Int
#endif

/// Simple Sendable struct for download info.
nonisolated enum DownloadContentKind: Equatable, Sendable {
  case pages
  case archiveImages(DownloadedImageArchiveFormat)
  case epubWebPub
  case epubDivina
  case pdf
}

nonisolated enum DownloadedImageArchiveFormat: Equatable, Sendable {
  case cbz
  case cbr

  init?(fileExtension: String) {
    switch fileExtension.lowercased() {
    case "cbz":
      self = .cbz
    case "cbr":
      self = .cbr
    default:
      return nil
    }
  }

  var fileName: String {
    switch self {
    case .cbz:
      return "book.cbz"
    case .cbr:
      return "book.cbr"
    }
  }
}

struct DownloadInfo: Sendable {
  let bookId: String
  let seriesTitle: String?
  let bookInfo: String
  let kind: DownloadContentKind
}

/// Actor for managing offline book downloads with proper thread isolation.
/// Download status is persisted in the local database via KomgaBook.downloadStatus.
/// Progress is tracked via DownloadProgressTracker for UI display.
@globalActor
actor OfflineManager {
  private struct ArchivePathIndexCacheKey: Hashable {
    let path: String
    let fileSize: Int64
    let modificationTime: TimeInterval
  }

  static let shared = OfflineManager()

  private var activeTasks: [String: Task<Void, Never>] = [:]
  private var readingDownloadRequests: [String: (instanceId: String, info: DownloadInfo)] = [:]
  private var readingDownloadRequestOrder: [String] = []
  private var syncTask: Task<Void, Never>?
  private var syncTaskID: UUID?
  private var isProcessingQueue = false
  private var completedDownloadsSinceLastNotification = 0
  /// Deletions staged behind an undo toast stay fully intact until the toast settles;
  /// the Offline pages filter these books out so rows look removed immediately.
  private var pendingDeletions: [UUID: PendingDownloadDeletion] = [:]
  #if os(iOS)
    private var foregroundDownloadInfoByBookId: [String: (instanceId: String, info: DownloadInfo)] = [:]
    private var liveActivityProgressSnapshots: [String: (progress: Double, updatedAt: Date)] = [:]
  #endif

  private let logger = AppLogger(.offline)
  private var pageImageCachesByInstanceId: [String: ImageCache] = [:]
  private var archivePathIndexesByCacheKey: [ArchivePathIndexCacheKey: [String: String]] = [:]
  private static let archivePathIndexCacheLimit = 8

  private init() {
    _ = NotificationCenter.default.addObserver(
      forName: .fileDownloadProgress,
      object: nil,
      queue: .main
    ) { notification in
      guard
        let bookId = notification.userInfo?[DownloadProgressUserInfo.itemKey] as? String
      else {
        return
      }

      let receivedBytes =
        notification.userInfo?[DownloadProgressUserInfo.receivedKey] as? Int64 ?? 0
      let expectedBytes = notification.userInfo?[DownloadProgressUserInfo.expectedKey] as? Int64

      Task { @MainActor in
        DownloadProgressTracker.shared.updateProgress(
          bookId: bookId,
          receivedBytes: receivedBytes,
          expectedBytes: expectedBytes
        )
      }
      #if os(iOS)
        Task {
          await self.updateDownloadLiveActivityProgress(
            bookId: bookId,
            receivedBytes: receivedBytes,
            expectedBytes: expectedBytes
          )
        }
      #endif
    }

    #if os(iOS)
      // Schedule callback setup on main actor
      Task { @MainActor in
        await self.setupBackgroundDownloadCallbacks()
      }
    #endif
  }

  #if os(iOS)
    private func setupBackgroundDownloadCallbacks() async {
      let manager = await MainActor.run { BackgroundDownloadManager.shared }

      await MainActor.run {
        manager.onDownloadComplete = { [weak self] bookId, pageNumber, fileURL in
          guard let self = self else { return }
          Task {
            await self.handleBackgroundDownloadComplete(
              bookId: bookId, pageNumber: pageNumber, fileURL: fileURL)
          }
        }

        manager.onDownloadFailed = { [weak self] bookId, pageNumber, error in
          guard let self = self else { return }
          Task {
            await self.handleBackgroundDownloadFailed(
              bookId: bookId, pageNumber: pageNumber, error: error)
          }
        }

        manager.onDownloadProgress = { [weak self] bookId, receivedBytes, expectedBytes in
          guard let self = self else { return }
          Task {
            await self.updateDownloadLiveActivityProgress(
              bookId: bookId,
              receivedBytes: receivedBytes,
              expectedBytes: expectedBytes
            )
          }
        }

        manager.onAllDownloadsComplete = { [weak self] bookId in
          guard let self = self else { return }
          Task {
            await self.handleAllBackgroundDownloadsComplete(bookId: bookId)
          }
        }
      }
    }
  #endif

  private static let directoryName = "OfflineBooks"
  private static let epubFileName = "book.epub"
  private static let pdfFileName = "book.pdf"
  private static let archivePagesFileName = ".archive-pages.json"
  private static let webPubManifestFileName = ".webpub-manifest.json"
  private static let pdfPreparationStampFileName = ".pdf-prepared.stamp"
  private nonisolated static let pdfPreparationStampVersion = "prepared-v4"

  nonisolated static func pdfPreparationCompletionFlag(
    renderQuality: PdfOfflineRenderQuality
  ) -> String {
    "\(pdfPreparationStampVersion)-\(renderQuality.rawValue)"
  }

  // MARK: - Paths

  /// Base directory for all offline books.
  private static func baseDirectory() -> URL {
    let supportDirectory = (try? AppStorageDirectory.supportDirectory()) ?? FileManager.default.temporaryDirectory
    let base = supportDirectory.appendingPathComponent(directoryName, isDirectory: true)
    migrateLegacyDirectoryIfNeeded(to: base)
    ensureDirectoryExists(at: base)
    excludeFromBackupIfNeeded(at: base)
    return base
  }

  /// Namespaced directory for a specific instance's offline books.
  private static func offlineDirectory(for instanceId: String) -> URL {
    let url = offlineDirectoryURL(for: instanceId)
    ensureDirectoryExists(at: url)
    excludeFromBackupIfNeeded(at: url)
    return url
  }

  /// On-disk location for an instance's offline books. Unlike `offlineDirectory`, never creates it.
  private static func offlineDirectoryURL(for instanceId: String) -> URL {
    let sanitized = instanceId.isEmpty ? "default" : instanceId
    return baseDirectory().appendingPathComponent(sanitized, isDirectory: true)
  }

  /// Remove all offline downloads for a specific instance.
  nonisolated static func removeOfflineData(for instanceId: String) {
    let url = offlineDirectoryURL(for: instanceId)
    try? FileManager.default.removeItem(at: url)
  }

  private func bookDirectory(instanceId: String, bookId: String) -> URL {
    let url = Self.offlineDirectory(for: instanceId)
      .appendingPathComponent(bookId, isDirectory: true)
    Self.ensureDirectoryExists(at: url)
    Self.excludeFromBackupIfNeeded(at: url)
    return url
  }

  /// On-disk location for a book's offline files. Unlike `bookDirectory`, never creates it.
  private static func bookDirectoryURL(instanceId: String, bookId: String) -> URL {
    offlineDirectoryURL(for: instanceId)
      .appendingPathComponent(bookId, isDirectory: true)
  }

  /// Removes the book's offline directory if present. Never creates it.
  private func removeBookDirectory(instanceId: String, bookId: String) {
    let dir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return }
    do {
      try FileManager.default.removeItem(at: dir)
      logger.info("🗑️ Removed offline directory for book: \(bookId)")
    } catch {
      logger.error("❌ Failed to remove offline directory \(bookId): \(error)")
    }
  }

  /// Removes the book's offline directory only when it holds no files, so downloads
  /// that failed or were cancelled before writing content don't leave empty shells
  /// behind. Directories with partial content are kept for resume on retry.
  private func removeBookDirectoryIfEmpty(instanceId: String, bookId: String) {
    let dir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
      isDir.boolValue, !Self.directoryContainsFiles(dir)
    else { return }
    do {
      try FileManager.default.removeItem(at: dir)
      logger.info("🗑️ Removed empty offline directory for book: \(bookId)")
    } catch {
      logger.error("❌ Failed to remove empty offline directory \(bookId): \(error)")
    }
  }

  /// On-disk location of a book's extracted WebPub root. Never creates it; write paths
  /// create the directory themselves when extracting resources.
  private static func webPubRootDirectoryURL(bookDir: URL) -> URL {
    bookDir.appendingPathComponent("webpub", isDirectory: true)
  }

  private static func webPubResourceURL(root: URL, href: String) -> URL {
    let relativePath = webPubRelativePath(from: href)
    return root.appendingPathComponent(relativePath, isDirectory: false)
  }

  private static func webPubRelativePath(from href: String) -> String {
    if let resourcePath = manifestResourcePath(from: href),
      let normalizedPath = normalizeArchivePath(resourcePath)
    {
      let components = normalizedPath.split(separator: "/").map(String.init)
      let sanitized =
        components.enumerated().map { index, component in
          let fallback = index == components.count - 1 ? "resource" : "dir"
          return sanitizePathComponent(component, fallback: fallback)
        }
      if !sanitized.isEmpty {
        return sanitized.joined(separator: "/")
      }
    }

    return legacyWebPubRelativePath(from: href)
  }

  private static func legacyWebPubRelativePath(from href: String) -> String {
    let cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      return FileNameHelper.sanitizedFileName("resource", defaultBaseName: "resource")
    }

    let hrefURL = URL(string: cleaned)
    let rawPath = hrefURL?.path.isEmpty == false ? hrefURL!.path : cleaned
    let trimmedPath = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let components = trimmedPath.split(separator: "/").map(String.init)

    var sanitized = components.enumerated().compactMap { index, component -> String? in
      if component == "." || component == ".." {
        return nil
      }
      let fallback = index == components.count - 1 ? "resource" : "dir"
      return sanitizePathComponent(component, fallback: fallback)
    }

    if sanitized.isEmpty {
      return FileNameHelper.sanitizedFileName("resource", defaultBaseName: "resource")
    }

    let query = URLComponents(string: cleaned)?.query
    if let query, !query.isEmpty {
      let suffix = "--q-" + sanitizePathComponent(query, fallback: "q")
      sanitized[sanitized.count - 1] += suffix
    }

    return sanitized.joined(separator: "/")
  }

  private static func sanitizePathComponent(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
    var sanitized = trimmed.components(separatedBy: invalidCharacters).joined(separator: "-")
    sanitized = sanitized.replacingOccurrences(of: " ", with: "-")

    while sanitized.contains("--") {
      sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
    }

    if sanitized.isEmpty {
      return fallback
    }

    return sanitized
  }

  // MARK: - Public API

  /// Get the download status of a book from the local database.
  func getDownloadStatus(bookId: String) async -> DownloadStatus {
    await getDownloadStatus(bookId: bookId, instanceId: AppConfig.current.instanceId)
  }

  func getDownloadStatus(bookId: String, instanceId: String) async -> DownloadStatus {
    (try? await DatabaseOperator.database().getDownloadStatus(bookId: bookId, instanceId: instanceId)) ?? .notDownloaded
  }

  /// Check if a book is downloaded.
  func isBookDownloaded(bookId: String) async -> Bool {
    await isBookDownloaded(bookId: bookId, instanceId: AppConfig.current.instanceId)
  }

  func isBookDownloaded(bookId: String, instanceId: String) async -> Bool {
    if case .downloaded = await getDownloadStatus(bookId: bookId, instanceId: instanceId) {
      return true
    }
    return false
  }

  func getOfflineWebPubRootURL(instanceId: String, bookId: String) async -> URL? {
    guard await isBookDownloaded(bookId: bookId) else { return nil }
    let root = Self.webPubRootDirectoryURL(
      bookDir: Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId))
    return FileManager.default.fileExists(atPath: root.path) ? root : nil
  }

  func cachedOfflineWebPubResourceURL(
    instanceId: String,
    bookId: String,
    href: String
  ) async -> URL? {
    guard await isBookDownloaded(bookId: bookId) else { return nil }
    let root = Self.webPubRootDirectoryURL(
      bookDir: Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId))
    let destination = Self.webPubResourceURL(root: root, href: href)
    if FileManager.default.fileExists(atPath: destination.path) {
      return destination
    }

    let legacyDestination = root.appendingPathComponent(
      Self.legacyWebPubRelativePath(from: href),
      isDirectory: false
    )
    if legacyDestination.path != destination.path,
      FileManager.default.fileExists(atPath: legacyDestination.path)
    {
      return legacyDestination
    }

    return nil
  }

  func toggleDownload(instanceId: String, info: DownloadInfo) async {
    // Toggling a book whose removal is still staged cancels the removal instead.
    if await isPendingDeletion(bookId: info.bookId) {
      await cancelPendingDeletion(forBookId: info.bookId)
      return
    }
    let status = await getDownloadStatus(bookId: info.bookId)
    switch status {
    case .downloaded:
      await deleteBookWithUndo(
        instanceId: instanceId, bookId: info.bookId,
        message: String(localized: "notification.book.offlineRemoved"))
    case .pending:
      await cancelDownloadWithUndo(
        instanceId: instanceId, bookId: info.bookId,
        message: String(localized: "notification.book.downloadCancelled"))
    case .notDownloaded, .failed:
      await cancelPendingDeletion(forBookId: info.bookId)
      await ensureSeriesRow(instanceId: instanceId, bookId: info.bookId)
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: info.bookId,
        instanceId: instanceId,
        status: .pending,
        downloadAt: .now
      )
      await postDownloadProjectionDidChange(bookId: info.bookId, instanceId: instanceId)
      await refreshQueueStatus(instanceId: instanceId)
      await syncDownloadQueue(instanceId: instanceId)
    }
  }

  /// Single-book download entries don't guarantee a local series row, which Offline
  /// series browse and series download rollups need; backfill it from the server.
  private func ensureSeriesRow(instanceId: String, bookId: String) async {
    do {
      let database = try await DatabaseOperator.database()
      guard let seriesId = await database.fetchMissingSeriesId(bookId: bookId, instanceId: instanceId)
      else { return }
      let series = try await SeriesService.getOneSeries(id: seriesId)
      await database.upsertSeries(dto: series, instanceId: instanceId)
      await database.syncSeriesDownloadStatus(seriesId: seriesId, instanceId: instanceId)
    } catch {
      logger.warning("⚠️ Failed to backfill series row for book \(bookId): \(error)")
    }
  }

  func retryDownload(instanceId: String, bookId: String) async {
    await cancelPendingDeletion(forBookId: bookId)
    await ensureSeriesRow(instanceId: instanceId, bookId: bookId)
    try? await DatabaseOperator.database().updateBookDownloadStatus(
      bookId: bookId,
      instanceId: instanceId,
      status: .pending,
      downloadAt: .now
    )
    await postDownloadProjectionDidChange(bookId: bookId, instanceId: instanceId)
    await refreshQueueStatus(instanceId: instanceId)
    await syncDownloadQueue(instanceId: instanceId)
  }

  func downloadForReading(instanceId: String, info: DownloadInfo) async {
    let status = await getDownloadStatus(bookId: info.bookId)

    switch status {
    case .downloaded:
      removeReadingDownloadRequest(bookId: info.bookId)
      return
    case .notDownloaded, .failed:
      await ensureSeriesRow(instanceId: instanceId, bookId: info.bookId)
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: info.bookId,
        instanceId: instanceId,
        status: .pending,
        downloadAt: .now
      )
      await postDownloadProjectionDidChange(bookId: info.bookId, instanceId: instanceId)
    case .pending:
      break
    }

    addReadingDownloadRequest(instanceId: instanceId, info: info)
    await refreshQueueStatus(instanceId: instanceId)
    _ = await startNextReadingDownload(instanceId: instanceId)
  }

  func deleteBook(
    instanceId: String, bookId: String, commit: Bool = true, syncSeriesStatus: Bool = true
  ) async {
    dropPendingDeletions(forBookIds: [bookId])
    await cancelDownload(
      bookId: bookId, instanceId: instanceId, commit: false, syncSeriesStatus: syncSeriesStatus)

    // Update local database
    try? await DatabaseOperator.database().updateBookDownloadStatus(
      bookId: bookId, instanceId: instanceId, status: .notDownloaded,
      syncSeriesStatus: syncSeriesStatus
    )
    if commit {
      await postDownloadProjectionDidChange(bookId: bookId, instanceId: instanceId)
      await refreshQueueStatus(instanceId: instanceId)
    }

    // Safety net: cancelDownload already removed the on-disk directory.
    removeBookDirectory(instanceId: instanceId, bookId: bookId)

    #if os(iOS) || os(macOS)
      SpotlightIndexService.removeBook(bookId: bookId, instanceId: instanceId)
    #endif
  }

  /// Delete the staged books, flipping their active protection sources to manual first
  /// when they must not be re-downloaded by a policy.
  private func deleteStagedBooks(
    _ entry: PendingDownloadDeletion, protectFromRedownload: Bool
  ) async {
    if protectFromRedownload {
      try? await DatabaseOperator.database().updateOfflineProtectionSourcesToManual(
        bookIds: entry.bookIds,
        instanceId: entry.instanceId
      )
    }
    for bookId in entry.bookIds {
      await deleteBook(
        instanceId: entry.instanceId, bookId: bookId, commit: false, syncSeriesStatus: false)
    }
    for seriesId in entry.seriesIds {
      try? await DatabaseOperator.database().syncSeriesDownloadStatus(
        seriesId: seriesId, instanceId: entry.instanceId)
    }
    // Also sync readlists containing these books
    try? await DatabaseOperator.database().syncReadListsContainingBooks(
      bookIds: entry.bookIds, instanceId: entry.instanceId)
    await postDownloadProjectionsDidChange(bookIds: entry.bookIds, instanceId: entry.instanceId)
    await refreshQueueStatus(instanceId: entry.instanceId)
  }

  /// Delete all read (completed) downloaded books for the current instance.
  func deleteReadBooks() async {
    let instanceId = AppConfig.current.instanceId
    let readBooks =
      (try? await DatabaseOperator.database().fetchReadBooksEligibleForAutoDelete(
        instanceId: instanceId
      )) ?? []

    if readBooks.isEmpty { return }

    let seriesIds = Set(readBooks.map { $0.seriesId })
    let bookIds = readBooks.map(\.id)

    for book in readBooks {
      await deleteBook(
        instanceId: instanceId, bookId: book.id, commit: false, syncSeriesStatus: false)
    }

    for seriesId in seriesIds {
      try? await DatabaseOperator.database().syncSeriesDownloadStatus(
        seriesId: seriesId, instanceId: instanceId)
    }
    // Also sync readlists containing these books
    try? await DatabaseOperator.database().syncReadListsContainingBooks(
      bookIds: bookIds, instanceId: instanceId)
    await postDownloadProjectionsDidChange(
      bookIds: bookIds,
      instanceId: instanceId
    )
    await refreshQueueStatus(instanceId: instanceId)
  }

  // MARK: - Pending Deletions (Undo)

  /// Book ids staged for deletion on one instance; Offline pages filter these out.
  func pendingDeletionBookIds(instanceId: String) -> Set<String> {
    Set(pendingDeletions.values.lazy.filter { $0.instanceId == instanceId }.flatMap(\.bookIds))
  }

  /// Stage downloaded books for deletion behind an undo toast. The real delete runs
  /// only when the toast settles; undo just drops the staged record.
  func deleteBooksWithUndo(
    seriesIds: Set<String>, instanceId: String, bookIds: [String], message: String
  ) async {
    await stagePendingDeletion(
      seriesIds: seriesIds, instanceId: instanceId, bookIds: bookIds, message: message,
      kind: .manualBooks)
  }

  func deleteAllDownloadedBooksWithUndo(message: String) async {
    let instanceId = AppConfig.current.instanceId
    let books =
      (try? await DatabaseOperator.database().fetchDownloadedBooks(instanceId: instanceId)) ?? []
    guard !books.isEmpty else { return }
    await stagePendingDeletion(
      seriesIds: Set(books.map(\.seriesId)), instanceId: instanceId, bookIds: books.map(\.id),
      message: message, kind: .allDownloaded)
  }

  func deleteReadBooksWithUndo(message: String) async {
    let instanceId = AppConfig.current.instanceId
    let books =
      (try? await DatabaseOperator.database().fetchReadBooksEligibleForAutoDelete(
        instanceId: instanceId
      )) ?? []
    guard !books.isEmpty else { return }
    await stagePendingDeletion(
      seriesIds: Set(books.map(\.seriesId)), instanceId: instanceId, bookIds: books.map(\.id),
      message: message, kind: .readBooks)
  }

  /// Stage a queue-task cancellation (pending/failed download) behind an undo toast.
  func cancelDownloadWithUndo(instanceId: String, bookId: String, message: String) async {
    await stagePendingDeletion(
      seriesIds: [], instanceId: instanceId, bookIds: [bookId], message: message,
      kind: .cancelDownload)
  }

  /// Stage a single downloaded book's removal behind an undo toast (plain delete on
  /// commit, mirroring toggle-off semantics — no protection-source flip).
  func deleteBookWithUndo(instanceId: String, bookId: String, message: String) async {
    await stagePendingDeletion(
      seriesIds: [], instanceId: instanceId, bookIds: [bookId], message: message,
      kind: .singleBook)
  }

  /// Stage a series' downloaded books for removal behind an undo toast.
  func removeSeriesOfflineWithUndo(
    seriesId: String, instanceId: String, readOnly: Bool, message: String
  ) async {
    let bookIds =
      (try? await DatabaseOperator.database().fetchSeriesDownloadedBookIds(
        seriesId: seriesId, instanceId: instanceId, readOnly: readOnly)) ?? []
    guard !bookIds.isEmpty else { return }
    await stagePendingDeletion(
      seriesIds: [seriesId], instanceId: instanceId, bookIds: bookIds, message: message,
      kind: readOnly ? .seriesRead(seriesId: seriesId) : .seriesAll(seriesId: seriesId))
  }

  /// Stage a read list's downloaded books for removal behind an undo toast.
  func removeReadListOfflineWithUndo(
    readListId: String, instanceId: String, readOnly: Bool, message: String
  ) async {
    let bookIds =
      (try? await DatabaseOperator.database().fetchReadListDownloadedBookIds(
        readListId: readListId, instanceId: instanceId, readOnly: readOnly)) ?? []
    guard !bookIds.isEmpty else { return }
    await stagePendingDeletion(
      seriesIds: [], instanceId: instanceId, bookIds: bookIds, message: message,
      kind: readOnly ? .readListRead(readListId: readListId) : .readListAll(readListId: readListId))
  }

  private func stagePendingDeletion(
    seriesIds: Set<String>, instanceId: String, bookIds: [String], message: String,
    kind: PendingDownloadDeletion.CommitKind
  ) async {
    let alreadyStaged = Set(pendingDeletions.values.flatMap(\.bookIds))
    let bookIds = bookIds.filter { !alreadyStaged.contains($0) }
    guard !bookIds.isEmpty else { return }
    let entryId = UUID()
    pendingDeletions[entryId] = PendingDownloadDeletion(
      id: entryId, instanceId: instanceId, seriesIds: seriesIds, bookIds: bookIds, kind: kind)
    let notificationId = await ErrorManager.shared.notifyUndo(
      message: message,
      commit: { [weak self] in await self?.commitPendingDeletion(id: entryId) },
      cancel: { [weak self] in await self?.cancelStagedDeletion(id: entryId) }
    )
    pendingDeletions[entryId]?.notificationId = notificationId
  }

  /// The toast's Undo drops the staged record; the books were never touched, so the
  /// queue-status bump is only to make the Offline pages reload and un-hide the rows.
  private func cancelStagedDeletion(id: UUID) async {
    guard let entry = pendingDeletions.removeValue(forKey: id) else { return }
    await refreshQueueStatus(instanceId: entry.instanceId)
  }

  /// Commits exactly the books captured at staging time: anything downloaded during
  /// the undo window was never staged and must survive.
  private func commitPendingDeletion(id: UUID) async {
    guard let entry = pendingDeletions.removeValue(forKey: id) else { return }
    switch entry.kind {
    case .manualBooks, .allDownloaded:
      await deleteStagedBooks(entry, protectFromRedownload: true)
    case .readBooks:
      await deleteStagedBooks(entry, protectFromRedownload: false)
    case .cancelDownload:
      for bookId in entry.bookIds {
        await cancelDownload(bookId: bookId, instanceId: entry.instanceId)
      }
      triggerSync(instanceId: entry.instanceId)
    case .singleBook:
      for bookId in entry.bookIds {
        await deleteBook(instanceId: entry.instanceId, bookId: bookId)
      }
    case .seriesAll(let seriesId):
      try? await DatabaseOperator.database().removeSeriesOffline(
        seriesId: seriesId, instanceId: entry.instanceId, onlyBookIds: Set(entry.bookIds))
    case .seriesRead(let seriesId):
      try? await DatabaseOperator.database().removeSeriesReadOffline(
        seriesId: seriesId, instanceId: entry.instanceId, onlyBookIds: Set(entry.bookIds))
    case .readListAll(let readListId):
      try? await DatabaseOperator.database().removeReadListOffline(
        readListId: readListId, instanceId: entry.instanceId, onlyBookIds: Set(entry.bookIds))
    case .readListRead(let readListId):
      try? await DatabaseOperator.database().removeReadListReadOffline(
        readListId: readListId, instanceId: entry.instanceId, onlyBookIds: Set(entry.bookIds))
    }
  }

  private func isPendingDeletion(bookId: String) -> Bool {
    pendingDeletions.values.contains { $0.bookIds.contains(bookId) }
  }

  /// An explicit (re)download supersedes a staged deletion of the same book: dismiss
  /// its toast like tapping Undo and keep the book.
  private func cancelPendingDeletion(forBookId bookId: String) async {
    guard let entry = pendingDeletions.values.first(where: { $0.bookIds.contains(bookId) })
    else { return }
    if let notificationId = entry.notificationId {
      await ErrorManager.shared.performAction(id: notificationId)
    } else {
      await cancelStagedDeletion(id: entry.id)
    }
  }

  /// A delete that already ran makes any staged record for the same books redundant:
  /// drop the record and dismiss its toast, whose commit and Undo would both no-op.
  private func dropPendingDeletions(forBookIds bookIds: [String]) {
    let stale = pendingDeletions.values.filter { entry in
      entry.bookIds.contains(where: bookIds.contains)
    }
    for entry in stale {
      pendingDeletions.removeValue(forKey: entry.id)
      if let notificationId = entry.notificationId {
        Task { await ErrorManager.shared.performAction(id: notificationId) }
      }
    }
  }

  /// Cleanup orphaned offline files that no longer have corresponding local database entries.
  /// Returns the number of orphaned directories deleted and total bytes freed.
  func cleanupOrphanedFiles() async -> (deletedCount: Int, bytesFreed: Int64) {
    let fm = FileManager.default
    let baseDir = Self.baseDirectory()
    guard let instanceDirNames = try? fm.contentsOfDirectory(atPath: baseDir.path) else {
      return (0, 0)
    }

    let currentInstanceId = AppConfig.current.instanceId
    var totalDeletedCount = 0
    var totalBytesFreed: Int64 = 0

    for instanceDirName in instanceDirNames {
      let instanceDir = baseDir.appendingPathComponent(instanceDirName)
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: instanceDir.path, isDirectory: &isDir), isDir.boolValue else {
        continue
      }

      // `offlineDirectory` maps an empty instance id to "default".
      let instanceId = instanceDirName == "default" ? "" : instanceDirName
      let result = await cleanupOrphanedBookDirectories(
        instanceId: instanceId,
        instanceDir: instanceDir,
        skipInFlight: instanceId == currentInstanceId
      )
      totalDeletedCount += result.deletedCount
      totalBytesFreed += result.bytesFreed

      if Self.isDirectoryEmpty(at: instanceDir) {
        try? fm.removeItem(at: instanceDir)
      }
    }

    if totalDeletedCount > 0 {
      logger.info(
        "✅ Cleanup complete: \(totalDeletedCount) orphaned directories, \(totalBytesFreed) bytes freed")
    }

    return (totalDeletedCount, totalBytesFreed)
  }

  private func cleanupOrphanedBookDirectories(
    instanceId: String,
    instanceDir: URL,
    skipInFlight: Bool
  ) async -> (deletedCount: Int, bytesFreed: Int64) {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: instanceDir.path) else {
      return (0, 0)
    }

    // Books with an active download state; anything else on disk is orphaned.
    let statusesByBookId =
      (try? await DatabaseOperator.database().fetchDownloadStatusesByBookId(instanceId: instanceId))
      ?? [:]

    var inFlightBookIds = Set<String>()
    if skipInFlight {
      inFlightBookIds.formUnion(activeTasks.keys)
      #if os(iOS)
        inFlightBookIds.formUnion(backgroundDownloadInfo.keys)
      #endif
    }

    var deletedCount = 0
    var bytesFreed: Int64 = 0
    var contentlessDownloadedBookIds: [String] = []

    for bookId in contents {
      let bookDir = instanceDir.appendingPathComponent(bookId)

      // Skip if not a directory
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: bookDir.path, isDirectory: &isDir), isDir.boolValue else {
        continue
      }

      if inFlightBookIds.contains(bookId) {
        continue
      }

      let hasFiles = Self.directoryContainsFiles(bookDir)
      switch statusesByBookId[bookId] {
      case "downloaded":
        // A downloaded book whose directory holds no files lost its content (purged
        // cache or interrupted finalize): drop the shell and reset its status below
        // so it no longer reads as downloaded.
        guard !hasFiles else { continue }
        contentlessDownloadedBookIds.append(bookId)
      case .some:
        // Pending/failed downloads keep partial content for resume on retry.
        guard !hasFiles else { continue }
      case .none:
        break
      }

      if let size = try? Self.calculateDirectorySize(bookDir) {
        bytesFreed += size
      }

      do {
        try fm.removeItem(at: bookDir)
        deletedCount += 1
        logger.info("🗑️ Cleaned up orphaned offline directory: \(bookId)")
      } catch {
        logger.error("❌ Failed to cleanup orphaned directory \(bookId): \(error)")
      }
    }

    for bookId in contentlessDownloadedBookIds {
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: bookId, instanceId: instanceId, status: .notDownloaded)
    }
    if !contentlessDownloadedBookIds.isEmpty {
      await postDownloadProjectionsDidChange(
        bookIds: contentlessDownloadedBookIds, instanceId: instanceId)
    }

    return (deletedCount, bytesFreed)
  }

  func cancelDownload(
    bookId: String, instanceId: String? = nil, commit: Bool = true, syncSeriesStatus: Bool = true
  ) async {
    removeActiveTask(bookId)
    let resolvedInstanceId = instanceId ?? AppConfig.current.instanceId
    #if os(iOS)
      await BackgroundDownloadManager.shared.cancelDownloads(forBookId: bookId)
      clearBackgroundDownloadContext(bookId: bookId)
    #endif
    try? await DatabaseOperator.database().updateBookDownloadStatus(
      bookId: bookId, instanceId: resolvedInstanceId, status: .notDownloaded,
      syncSeriesStatus: syncSeriesStatus
    )
    removeBookDirectory(instanceId: resolvedInstanceId, bookId: bookId)
    if commit {
      await postDownloadProjectionDidChange(bookId: bookId, instanceId: resolvedInstanceId)
      await refreshQueueStatus(instanceId: resolvedInstanceId)
    }
  }

  func cancelReadListDownload(readListId: String, instanceId: String) async {
    guard let database = try? await DatabaseOperator.database() else {
      return
    }

    let bookIds = await database.prepareReadListDownloadCancellation(
      readListId: readListId,
      instanceId: instanceId
    )
    guard !bookIds.isEmpty else {
      await database.syncReadListDownloadStatus(readListId: readListId, instanceId: instanceId)
      await refreshQueueStatus(instanceId: instanceId)
      return
    }

    for bookId in bookIds {
      await cancelDownload(
        bookId: bookId,
        instanceId: instanceId,
        commit: false,
        syncSeriesStatus: true
      )
    }
    await database.syncReadListDownloadStatus(readListId: readListId, instanceId: instanceId)
    await postDownloadProjectionsDidChange(bookIds: bookIds, instanceId: instanceId)
    await refreshQueueStatus(instanceId: instanceId)
  }

  /// Cancel all active downloads (used during cleanup).
  func cancelAllDownloads() async {
    let instanceId = AppConfig.current.instanceId
    let bookIds = Array(activeTasks.keys)
    for (bookId, task) in activeTasks {
      task.cancel()
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: bookId, instanceId: instanceId, status: .notDownloaded
      )
    }
    activeTasks.removeAll()
    await postDownloadProjectionsDidChange(bookIds: bookIds, instanceId: instanceId)
    await MainActor.run {
      for bookId in bookIds {
        DownloadProgressTracker.shared.clearProgress(bookId: bookId)
      }
      DownloadProgressTracker.shared.finishDownload()
    }
    #if os(iOS)
      await LiveActivityManager.shared.endActivity()
    #endif
    await refreshQueueStatus(instanceId: instanceId)
  }

  func retryFailedDownloads(instanceId: String) async {
    let failedBookIds =
      ((try? await DatabaseOperator.database().fetchOfflineTaskItems(instanceId: instanceId)) ?? [])
      .filter { $0.isFailed }
      .map(\.bookId)
    try? await DatabaseOperator.database().retryFailedBooks(instanceId: instanceId)
    await postDownloadProjectionsDidChange(bookIds: failedBookIds, instanceId: instanceId)
    await refreshQueueStatus(instanceId: instanceId)
    await syncDownloadQueue(instanceId: instanceId)
  }

  func cancelFailedDownloads(instanceId: String) async {
    let failedBookIds =
      ((try? await DatabaseOperator.database().fetchOfflineTaskItems(instanceId: instanceId)) ?? [])
      .filter { $0.isFailed }
      .map(\.bookId)
    try? await DatabaseOperator.database().cancelFailedBooks(instanceId: instanceId)
    await postDownloadProjectionsDidChange(bookIds: failedBookIds, instanceId: instanceId)
    await refreshQueueStatus(instanceId: instanceId)
  }

  /// Trigger the download queue processing in the background.
  /// - Parameter restart: If true, cancels any pending debounce and runs immediately.
  nonisolated func triggerSync(instanceId: String, restart: Bool = false) {
    Task {
      await performDebouncedSync(instanceId: instanceId, restart: restart)
    }
  }

  private func performDebouncedSync(instanceId: String, restart: Bool) async {
    syncTask?.cancel()

    let currentID = UUID()
    syncTaskID = currentID

    syncTask = Task {
      if !restart {
        try? await Task.sleep(for: .seconds(2))
      }

      guard !Task.isCancelled else { return }

      // If we are still the current task (didn't get replaced during sleep),
      // we clear the reference so future triggers don't cancel us while we run.
      if syncTaskID == currentID {
        syncTask = nil
        syncTaskID = nil
      }

      await syncDownloadQueue(instanceId: instanceId)
    }
  }

  private func startBackgroundTask() async -> BackgroundTaskID {
    #if os(iOS)
      return await MainActor.run {
        UIApplication.shared.beginBackgroundTask(withName: "OfflineMetadataFetch") {
          // If the task expires, there's not much we can do but log it
        }
      }
    #else
      return 0
    #endif
  }

  private func endBackgroundTask(_ identifier: BackgroundTaskID) async {
    #if os(iOS)
      if identifier != .invalid {
        await MainActor.run {
          UIApplication.shared.endBackgroundTask(identifier)
        }
      }
    #endif
  }

  private func syncDownloadQueue(instanceId: String) async {
    // Check if offline
    guard !AppConfig.isOffline else { return }

    if await startNextReadingDownload(instanceId: instanceId) {
      return
    }

    // Check if paused
    guard !AppConfig.offlinePaused else { return }
    guard !isProcessingQueue else { return }

    // Only allow one download at a time
    guard activeTasks.isEmpty else { return }

    let backgroundTaskId = await startBackgroundTask()
    defer {
      Task {
        await endBackgroundTask(backgroundTaskId)
      }
    }

    isProcessingQueue = true
    defer { isProcessingQueue = false }

    // Auto-delete read books if enabled
    if AppConfig.offlineAutoDeleteRead {
      await deleteReadBooks()
    }

    await syncMissingOfflineEpubProgressions(instanceId: instanceId)

    let pending =
      (try? await DatabaseOperator.database().fetchPendingBooks(instanceId: instanceId)) ?? []

    guard let nextBook = pending.first else {
      if completedDownloadsSinceLastNotification > 0 {
        completedDownloadsSinceLastNotification = 0
        let failedCount =
          (try? await DatabaseOperator.database().fetchFailedBooksCount(
            instanceId: instanceId
          )) ?? 0
        if failedCount == 0 {
          await MainActor.run {
            ErrorManager.shared.notify(
              message: String(localized: "notification.offline.tasksCompleted")
            )
          }
        }
      }
      return
    }

    // Proceed to download even if it's read, as it was likely manually requested or reader is opening it.
    await startDownload(instanceId: instanceId, info: nextBook.downloadInfo)
  }

  private func addReadingDownloadRequest(instanceId: String, info: DownloadInfo) {
    if readingDownloadRequests[info.bookId] == nil {
      readingDownloadRequestOrder.append(info.bookId)
    }
    readingDownloadRequests[info.bookId] = (instanceId: instanceId, info: info)
  }

  private func removeReadingDownloadRequest(bookId: String) {
    readingDownloadRequests.removeValue(forKey: bookId)
    readingDownloadRequestOrder.removeAll { $0 == bookId }
  }

  private func startNextReadingDownload(instanceId: String) async -> Bool {
    guard !AppConfig.isOffline else { return false }
    guard activeTasks.isEmpty else { return false }

    while let bookId = readingDownloadRequestOrder.first(where: {
      readingDownloadRequests[$0]?.instanceId == instanceId
    }) {
      guard let request = readingDownloadRequests[bookId] else {
        readingDownloadRequestOrder.removeAll { $0 == bookId }
        continue
      }

      let status = await getDownloadStatus(bookId: bookId)
      switch status {
      case .pending:
        removeReadingDownloadRequest(bookId: bookId)
        await startDownload(instanceId: request.instanceId, info: request.info)
        return true
      case .downloaded, .notDownloaded, .failed:
        removeReadingDownloadRequest(bookId: bookId)
      }
    }

    return false
  }

  private func syncMissingOfflineEpubProgressions(instanceId: String) async {
    let bookIds =
      (try? await DatabaseOperator.database().fetchOfflineEpubBookIdsMissingProgression(
        instanceId: instanceId
      )) ?? []
    guard !bookIds.isEmpty else { return }

    logger.info(
      "📥 Syncing missing EPUB progression for \(bookIds.count) offline books with non-zero progress"
    )

    var syncedCount = 0
    var failedCount = 0

    for bookId in bookIds {
      let remoteState = await BookService.fetchRemoteWebPubProgression(bookId: bookId)

      switch remoteState {
      case .available(let progression):
        try? await DatabaseOperator.database().updateBookEpubProgression(
          bookId: bookId,
          progression: progression
        )
        syncedCount += 1
      case .missing:
        try? await DatabaseOperator.database().updateBookEpubProgression(
          bookId: bookId,
          progression: nil
        )
        syncedCount += 1
        logger.info(
          "⏭️ Marked missing remote EPUB progression as handled for offline book \(bookId)"
        )
      case .retryableFailure(let error):
        failedCount += 1
        logger.warning(
          "⚠️ Failed to sync missing EPUB progression for offline book \(bookId): \(error.localizedDescription)"
        )
      case .invalidPayload(let error):
        try? await DatabaseOperator.database().updateBookEpubProgression(
          bookId: bookId,
          progression: nil
        )
        syncedCount += 1
        logger.warning(
          "⏭️ Ignoring non-retryable remote EPUB progression payload for offline book \(bookId): \(error.localizedDescription)"
        )
      }
    }

    if syncedCount > 0 {
    }

    logger.info(
      "✅ Finished syncing missing EPUB progression for offline books: synced=\(syncedCount), failed=\(failedCount)"
    )
  }

  private func startDownload(instanceId: String, info: DownloadInfo) async {
    guard activeTasks[info.bookId] == nil else { return }

    await ensureSeriesRow(instanceId: instanceId, bookId: info.bookId)

    logger.info("📥 Enqueue download: \(info.bookId)")
    // Initialize progress (status stays as pending during download)
    await MainActor.run {
      DownloadProgressTracker.shared.startDownload(bookName: info.bookInfo)
      DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: 0.0)
    }

    let bookDir = bookDirectory(instanceId: instanceId, bookId: info.bookId)

    #if os(iOS)
      // Use background downloads on iOS for all content kinds.
      await startBackgroundDownload(instanceId: instanceId, info: info, bookDir: bookDir)
    #else
      // Use in-process downloads on macOS/tvOS
      await startForegroundDownload(instanceId: instanceId, info: info, bookDir: bookDir)
    #endif
  }

  #if os(iOS)
    private func startBackgroundDownload(
      instanceId: String, info: DownloadInfo, bookDir: URL
    ) async {
      logger.info("⬇️ Starting background download for book: \(info.bookInfo) (\(info.bookId))")

      do {
        // Get pending count and failed count for Live Activity
        let pendingBooks =
          (try? await DatabaseOperator.database().fetchPendingBooks(instanceId: instanceId)) ?? []
        let failedCount =
          (try? await DatabaseOperator.database().fetchFailedBooksCount(
            instanceId: instanceId
          )) ?? 0

        // Start or update Live Activity for download progress
        await LiveActivityManager.shared.startActivity(
          seriesTitle: info.seriesTitle,
          bookInfo: info.bookInfo,
          totalBooks: pendingBooks.count + 1,
          pendingCount: pendingBooks.count,
          failedCount: failedCount
        )

        switch info.kind {
        case .epubWebPub:
          try await savePageMetadataFromServer(bookId: info.bookId, bookDir: bookDir)
          let webPubManifest = try await BookService.getBookWebPubManifest(bookId: info.bookId)
          try? await DatabaseOperator.database().updateBookWebPubManifest(
            bookId: info.bookId,
            manifest: webPubManifest
          )
          try Self.writeWebPubManifestSidecar(webPubManifest, to: bookDir)
          try await scheduleBackgroundEpubDownload(
            instanceId: instanceId,
            info: info,
            bookDir: bookDir
          )
        case .epubDivina:
          let manifest = try await BookService.getBookManifest(id: info.bookId)
          await saveDivinaManifestTOC(bookId: info.bookId, manifest: manifest)
          try await savePageMetadataFromServer(bookId: info.bookId, bookDir: bookDir)
          try await scheduleBackgroundEpubDownload(
            instanceId: instanceId,
            info: info,
            bookDir: bookDir
          )
        case .pdf:
          try await savePageMetadataFromServer(bookId: info.bookId)
          try await scheduleBackgroundPdfDownload(
            instanceId: instanceId,
            info: info,
            bookDir: bookDir
          )
        case .archiveImages(let format):
          try await savePageMetadataFromServer(bookId: info.bookId, bookDir: bookDir)
          try await scheduleBackgroundImageArchiveDownload(
            instanceId: instanceId,
            info: info,
            format: format,
            bookDir: bookDir
          )
        case .pages:
          let pages = try await savePageMetadataFromServer(bookId: info.bookId, bookDir: bookDir)
          await saveDivinaManifestTOCFromServerIfAvailable(bookId: info.bookId)
          try await scheduleBackgroundPageDownloads(
            instanceId: instanceId,
            info: info,
            bookDir: bookDir,
            pages: pages,
            pendingCount: pendingBooks.count,
            failedCount: failedCount
          )
        }
      } catch {
        if isPermanentNotFound(error) {
          logger.info(
            "🧹 Book \(info.bookId) no longer exists on server; removing local record"
          )
          await removeBookAfterPermanentNotFound(bookId: info.bookId, instanceId: instanceId)
          await syncDownloadQueue(instanceId: instanceId)
          return
        }
        logger.error("❌ Failed to start background download for \(info.bookId): \(error)")
        await BackgroundDownloadManager.shared.cancelDownloads(forBookId: info.bookId)
        clearBackgroundDownloadContext(bookId: info.bookId)
        removeActiveTask(info.bookId)
        removeBookDirectoryIfEmpty(instanceId: instanceId, bookId: info.bookId)
        try? await DatabaseOperator.database().updateBookDownloadStatus(
          bookId: info.bookId,
          instanceId: instanceId,
          status: .failed(error: error.diagnosticDescription)
        )
        await postDownloadProjectionDidChange(bookId: info.bookId, instanceId: instanceId)
        await refreshQueueStatus(instanceId: instanceId)
        await syncDownloadQueue(instanceId: instanceId)
      }
    }

    private func scheduleBackgroundPageDownloads(
      instanceId: String,
      info: DownloadInfo,
      bookDir: URL,
      pages: [BookPage],
      pendingCount: Int,
      failedCount: Int
    ) async throws {
      let totalTaskCount = pages.count
      guard totalTaskCount > 0 else {
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: 1.0)
        }
        await finalizeDownload(instanceId: instanceId, bookId: info.bookId, bookDir: bookDir)
        await syncDownloadQueue(instanceId: instanceId)
        return
      }

      let serverURL = await MainActor.run { AppConfig.current.serverURL }
      var pagesToDownload: [BookPage] = []

      for page in pages {
        let ext = page.detectedUTType?.preferredFilenameExtension ?? "jpg"
        let destination = bookDir.appendingPathComponent("page-\(page.number).\(ext)")

        if FileManager.default.fileExists(atPath: destination.path) {
          continue
        }
        if await copyCachedPageIfAvailable(
          instanceId: instanceId,
          bookId: info.bookId,
          page: page,
          destination: destination
        ) {
          continue
        }
        pagesToDownload.append(page)
      }

      let completedTaskCount = totalTaskCount - pagesToDownload.count
      if pagesToDownload.isEmpty {
        logger.info("✅ All pages already downloaded for book: \(info.bookId)")
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: 1.0)
        }
        await finalizeDownload(instanceId: instanceId, bookId: info.bookId, bookDir: bookDir)
        await syncDownloadQueue(instanceId: instanceId)
        return
      }

      registerBackgroundDownloadContext(
        bookId: info.bookId,
        instanceId: instanceId,
        seriesTitle: info.seriesTitle,
        bookInfo: info.bookInfo,
        kind: info.kind,
        totalTasks: totalTaskCount,
        completedTasks: completedTaskCount
      )

      if completedTaskCount > 0 {
        let initialProgress = Double(completedTaskCount) / Double(totalTaskCount)
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: initialProgress)
        }
        await LiveActivityManager.shared.updateActivity(
          seriesTitle: info.seriesTitle,
          bookInfo: info.bookInfo,
          progress: initialProgress,
          pendingCount: pendingCount,
          failedCount: failedCount
        )
      }

      for page in pagesToDownload {
        guard
          let downloadURL = URL(
            string: serverURL + "/api/v1/books/\(info.bookId)/pages/\(page.number)")
        else {
          throw AppErrorType.invalidFileURL(url: "/api/v1/books/\(info.bookId)/pages/\(page.number)")
        }

        let ext = page.detectedUTType?.preferredFilenameExtension ?? "jpg"
        let destinationPath = bookDir.appendingPathComponent("page-\(page.number).\(ext)").path

        await MainActor.run {
          BackgroundDownloadManager.shared.downloadPage(
            bookId: info.bookId,
            instanceId: instanceId,
            pageNumber: page.number,
            url: downloadURL,
            destinationPath: destinationPath
          )
        }
      }
    }

    private func scheduleBackgroundPdfDownload(
      instanceId: String,
      info: DownloadInfo,
      bookDir: URL
    ) async throws {
      let destinationURL = bookDir.appendingPathComponent(Self.pdfFileName)
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        logger.info("✅ Background PDF already exists for book: \(info.bookId)")
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: 1.0)
        }
        await finalizeDownload(instanceId: instanceId, bookId: info.bookId, bookDir: bookDir)
        await syncDownloadQueue(instanceId: instanceId)
        return
      }

      let serverURL = await MainActor.run { AppConfig.current.serverURL }
      guard let downloadURL = URL(string: serverURL + "/api/v1/books/\(info.bookId)/file") else {
        throw AppErrorType.invalidFileURL(url: "/api/v1/books/\(info.bookId)/file")
      }

      registerBackgroundDownloadContext(
        bookId: info.bookId,
        instanceId: instanceId,
        seriesTitle: info.seriesTitle,
        bookInfo: info.bookInfo,
        kind: info.kind,
        totalTasks: 1,
        completedTasks: 0
      )

      await MainActor.run {
        BackgroundDownloadManager.shared.downloadFile(
          bookId: info.bookId,
          instanceId: instanceId,
          url: downloadURL,
          destinationPath: destinationURL.path,
          reportByteProgress: true
        )
      }
    }

    private func scheduleBackgroundImageArchiveDownload(
      instanceId: String,
      info: DownloadInfo,
      format: DownloadedImageArchiveFormat,
      bookDir: URL
    ) async throws {
      let destinationURL = bookDir.appendingPathComponent(format.fileName)
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        logger.info("✅ Background image archive already exists for book: \(info.bookId)")
        try await finalizeExistingImageArchiveFile(info: info, bookDir: bookDir)
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: 1.0)
        }
        await finalizeDownload(instanceId: instanceId, bookId: info.bookId, bookDir: bookDir)
        await syncDownloadQueue(instanceId: instanceId)
        return
      }

      let serverURL = await MainActor.run { AppConfig.current.serverURL }
      guard let downloadURL = URL(string: serverURL + "/api/v1/books/\(info.bookId)/file") else {
        throw AppErrorType.invalidFileURL(url: "/api/v1/books/\(info.bookId)/file")
      }

      registerBackgroundDownloadContext(
        bookId: info.bookId,
        instanceId: instanceId,
        seriesTitle: info.seriesTitle,
        bookInfo: info.bookInfo,
        kind: info.kind,
        totalTasks: 1,
        completedTasks: 0
      )

      await MainActor.run {
        BackgroundDownloadManager.shared.downloadFile(
          bookId: info.bookId,
          instanceId: instanceId,
          url: downloadURL,
          destinationPath: destinationURL.path,
          reportByteProgress: true
        )
      }
    }

    private func scheduleBackgroundEpubDownload(
      instanceId: String,
      info: DownloadInfo,
      bookDir: URL
    ) async throws {
      let destinationURL = bookDir.appendingPathComponent(Self.epubFileName)
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        do {
          try await validateEpubArchiveFile(destinationURL, bookId: info.bookId)
        } catch {
          logger.warning(
            "⚠️ Existing EPUB failed validation, removing and redownloading: \(info.bookId): \(error.diagnosticDescription)"
          )
          try? FileManager.default.removeItem(at: destinationURL)
        }
      }
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        logger.info("✅ Background EPUB already exists for book: \(info.bookId)")
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: info.bookId, value: 1.0)
        }
        await finalizeDownload(instanceId: instanceId, bookId: info.bookId, bookDir: bookDir)
        await syncDownloadQueue(instanceId: instanceId)
        return
      }

      let serverURL = await MainActor.run { AppConfig.current.serverURL }
      guard let downloadURL = URL(string: serverURL + "/api/v1/books/\(info.bookId)/file") else {
        throw AppErrorType.invalidFileURL(url: "/api/v1/books/\(info.bookId)/file")
      }

      registerBackgroundDownloadContext(
        bookId: info.bookId,
        instanceId: instanceId,
        seriesTitle: info.seriesTitle,
        bookInfo: info.bookInfo,
        kind: info.kind,
        totalTasks: 1,
        completedTasks: 0
      )

      await MainActor.run {
        BackgroundDownloadManager.shared.downloadEpub(
          bookId: info.bookId,
          instanceId: instanceId,
          url: downloadURL,
          destinationPath: destinationURL.path
        )
      }
    }

    private func registerBackgroundDownloadContext(
      bookId: String,
      instanceId: String,
      seriesTitle: String?,
      bookInfo: String,
      kind: DownloadContentKind,
      totalTasks: Int,
      completedTasks: Int
    ) {
      backgroundDownloadInfo[bookId] = (
        instanceId: instanceId,
        seriesTitle: seriesTitle,
        bookInfo: bookInfo,
        kind: kind
      )
      backgroundDownloadTotalTasks[bookId] = totalTasks
      backgroundDownloadCompletedTasks[bookId] = min(max(completedTasks, 0), totalTasks)

      activeTasks[bookId] = Task {
        // Keep a placeholder task so queue state remains "active" until background callbacks finish.
        try? await Task.sleep(nanoseconds: UInt64.max)
      }
    }

    private func clearBackgroundDownloadContext(bookId: String) {
      backgroundDownloadInfo.removeValue(forKey: bookId)
      backgroundDownloadTotalTasks.removeValue(forKey: bookId)
      backgroundDownloadCompletedTasks.removeValue(forKey: bookId)
      backgroundDownloadFinalizingBooks.remove(bookId)
      liveActivityProgressSnapshots.removeValue(forKey: bookId)
    }
  #endif

  private func startForegroundDownload(
    instanceId: String, info: DownloadInfo, bookDir: URL
  ) async {
    #if os(iOS)
      foregroundDownloadInfoByBookId[info.bookId] = (instanceId: instanceId, info: info)
      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(instanceId: instanceId)) ?? []
      let failedCount =
        (try? await DatabaseOperator.database().fetchFailedBooksCount(instanceId: instanceId))
        ?? 0
      await LiveActivityManager.shared.startActivity(
        seriesTitle: info.seriesTitle,
        bookInfo: info.bookInfo,
        totalBooks: pendingBooks.count + 1,
        pendingCount: pendingBooks.count,
        failedCount: failedCount
      )
    #endif

    activeTasks[info.bookId] = Task { [weak self, logger] in
      guard let self else { return }
      do {
        logger.info("⬇️ Starting download for book: \(info.bookInfo) (\(info.bookId))")

        switch info.kind {
        case .epubWebPub, .epubDivina:
          try await downloadEpub(bookId: info.bookId, kind: info.kind, to: bookDir)
        case .pdf:
          try await downloadPdfFile(bookId: info.bookId, to: bookDir)
        case .archiveImages(let format):
          try await downloadImageArchive(bookId: info.bookId, format: format, to: bookDir)
        case .pages:
          try await downloadPages(instanceId: instanceId, bookId: info.bookId, to: bookDir)
        }

        #if os(iOS)
          await self.updateDownloadLiveActivityProcessing(
            bookId: info.bookId,
            instanceId: instanceId,
            seriesTitle: info.seriesTitle,
            kind: info.kind
          )
        #endif

        // Mark complete in local database
        await finalizeDownload(
          instanceId: instanceId,
          bookId: info.bookId,
          bookDir: bookDir
        )
        #if os(iOS)
          await self.finishForegroundLiveActivity(bookId: info.bookId, instanceId: instanceId)
        #endif
        logger.info("✅ Download complete for book: \(info.bookId)")

        // Trigger next download
        await syncDownloadQueue(instanceId: instanceId)

      } catch {
        if Task.isCancelled {
          try? FileManager.default.removeItem(at: bookDir)
          logger.info("⛔ Download cancelled for book: \(info.bookId)")
        } else if self.isPermanentNotFound(error) {
          logger.info(
            "🧹 Book \(info.bookId) no longer exists on server; removing local record"
          )
          await self.removeBookAfterPermanentNotFound(bookId: info.bookId, instanceId: instanceId)
          #if os(iOS)
            await self.finishForegroundLiveActivity(bookId: info.bookId, instanceId: instanceId)
          #endif
          await syncDownloadQueue(instanceId: instanceId)
          return
        } else {
          try? FileManager.default.removeItem(at: bookDir)
          let shouldKeepPending = await self.shouldKeepPendingAfterNetworkFailure(error)
          if shouldKeepPending {
            // Keep status as pending so foreground retry can continue later.
            logger.info("⚠️ Download paused due to transient network issue: \(info.bookId)")
            await removeActiveTask(info.bookId)
            #if os(iOS)
              await self.finishForegroundLiveActivity(bookId: info.bookId, instanceId: instanceId)
            #endif
            if AppConfig.isOffline {
              await syncDownloadQueue(instanceId: instanceId)
            }
            return
          } else {
            logger.error("❌ Download failed for book \(info.bookId): \(error)")
            try? await DatabaseOperator.database().updateBookDownloadStatus(
              bookId: info.bookId,
              instanceId: instanceId,
              status: .failed(error: error.diagnosticDescription)
            )
            await self.postDownloadProjectionDidChange(bookId: info.bookId, instanceId: instanceId)
            await self.refreshQueueStatus(instanceId: instanceId)
          }
        }
        await removeActiveTask(info.bookId)
        #if os(iOS)
          await self.finishForegroundLiveActivity(bookId: info.bookId, instanceId: instanceId)
        #endif

        // Trigger next download even on failure or cancellation
        await syncDownloadQueue(instanceId: instanceId)
      }
    }
  }

  func cancelDownload(bookId: String) async {
    let instanceId = AppConfig.current.instanceId
    await cancelDownload(bookId: bookId, instanceId: instanceId)
  }

  // MARK: - Accessors for Reader

  func getOfflinePageImageURL(
    instanceId: String, bookId: String, pageNumber: Int, fileExtension: String
  ) async throws -> URL? {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return nil }
    let dir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)

    let file = dir.appendingPathComponent("page-\(pageNumber).\(fileExtension)")
    if FileManager.default.fileExists(atPath: file.path) {
      return file
    }
    if let database = try? await DatabaseOperator.database() {
      let pages = await database.fetchPages(id: bookId, instanceId: instanceId)
      if let page = pages?.first(where: { $0.number == pageNumber }) {
        return try await getOfflinePageImageURL(instanceId: instanceId, bookId: bookId, page: page)
      }
    }
    return nil
  }

  func getOfflinePageImageURL(
    instanceId: String, bookId: String, page: BookPage
  ) async throws -> URL? {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return nil }
    let dir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)

    for file in offlinePageImageFileURLs(bookDir: dir, page: page) {
      if FileManager.default.fileExists(atPath: file.path) {
        return file
      }
    }

    let cache = pageImageCache(for: instanceId)
    if await cache.hasImage(bookId: bookId, page: page) {
      return cache.imageFileURL(bookId: bookId, page: page)
    }

    guard let archiveFile = existingArchivedPageSourceURL(in: dir) else {
      return nil
    }

    do {
      let data = try await archivedPageData(from: archiveFile, page: page)

      await cache.storeImageData(data, bookId: bookId, page: page)
      let cachedURL = cache.imageFileURL(bookId: bookId, page: page)
      return FileManager.default.fileExists(atPath: cachedURL.path) ? cachedURL : nil
    } catch {
      logger.error(
        "❌ Failed to materialize archived page \(page.number) for book \(bookId): \(error)"
      )
      throw error
    }
  }

  func fillMissingPageDimensions(
    instanceId: String,
    bookId: String,
    pages: [BookPage]
  ) async -> [BookPage] {
    let pagesMissingDimensions = pages.filter { !$0.hasValidDimensions }
    guard !pagesMissingDimensions.isEmpty else { return pages }

    let bookDir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)
    let cache = pageImageCache(for: instanceId)
    var localFileURLsByEntryPath: [String: URL] = [:]

    for page in pagesMissingDimensions {
      let candidateURLs =
        offlinePageImageFileURLs(bookDir: bookDir, page: page) + [
          cache.imageFileURL(bookId: bookId, page: page)
        ]
      if let fileURL = candidateURLs.first(where: {
        FileManager.default.fileExists(atPath: $0.path)
      }) {
        localFileURLsByEntryPath[page.fileName] = fileURL
      }
    }

    var pixelSizesByEntryPath = await Task.detached(priority: .userInitiated) {
      localFileURLsByEntryPath.reduce(into: [String: CGSize]()) { result, item in
        if let pixelSize = ArchiveExtractionService.imagePixelSize(at: item.value) {
          result[item.key] = pixelSize
        }
      }
    }.value

    let unresolvedEntryPaths = Set(
      pagesMissingDimensions.lazy
        .map(\.fileName)
        .filter { pixelSizesByEntryPath[$0] == nil }
    )

    if !unresolvedEntryPaths.isEmpty,
      let archiveFile = existingArchivedPageSourceURL(in: bookDir)
    {
      do {
        let archivePixelSizes = try await Task.detached(priority: .userInitiated) {
          try ArchiveExtractionService.imagePixelSizes(
            from: archiveFile,
            entryPaths: unresolvedEntryPaths,
            normalizePath: Self.normalizeArchivePath
          )
        }.value
        pixelSizesByEntryPath.merge(archivePixelSizes) { current, _ in current }
      } catch {
        logger.warning(
          "⚠️ Failed to read missing page dimensions from archive for book \(bookId): \(error)"
        )
      }
    }

    guard !pixelSizesByEntryPath.isEmpty else { return pages }

    var resolvedCount = 0
    let resolvedPages = pages.map { page in
      guard !page.hasValidDimensions,
        let pixelSize = pixelSizesByEntryPath[page.fileName]
      else {
        return page
      }

      resolvedCount += 1
      return page.withDimensions(
        width: Int(pixelSize.width),
        height: Int(pixelSize.height)
      )
    }
    guard resolvedCount > 0 else { return pages }

    if let database = await DatabaseOperator.databaseIfConfigured() {
      await database.updateBookPages(
        bookId: bookId,
        instanceId: instanceId,
        pages: resolvedPages
      )
    }

    if existingArchivedPageSourceURL(in: bookDir) != nil {
      do {
        try Self.writeArchivePagesSidecar(resolvedPages, to: bookDir)
      } catch {
        logger.warning(
          "⚠️ Failed to persist resolved page dimensions sidecar for book \(bookId): \(error)"
        )
      }
    }

    logger.info(
      "✅ Filled missing page dimensions for book \(bookId): resolved=\(resolvedCount), missing=\(pagesMissingDimensions.count - resolvedCount)"
    )
    return resolvedPages
  }

  func storeOfflinePageImage(
    instanceId: String,
    bookId: String,
    pageNumber: Int,
    fileExtension: String,
    data: Data,
    replaceExisting: Bool = false
  ) async -> URL? {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return nil }
    let dir = bookDirectory(instanceId: instanceId, bookId: bookId)
    let file = dir.appendingPathComponent("page-\(pageNumber).\(fileExtension)")

    if FileManager.default.fileExists(atPath: file.path), !replaceExisting {
      return file
    }

    do {
      try data.write(to: file, options: .atomic)
      Self.excludeFromBackupIfNeeded(at: file)
      return file
    } catch {
      logger.error(
        "❌ Failed to store offline page image for book \(bookId) page \(pageNumber): \(error)")
      return nil
    }
  }

  func clearOfflinePageImageDerivatives(instanceId: String, bookId: String, pageNumber: Int) async {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return }
    let dir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)
    let baseName = "page-\(pageNumber)@2x"
    let candidates = ["png", "jpg", "jpeg"].map { fileExtension in
      dir.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
    }

    for fileURL in candidates where FileManager.default.fileExists(atPath: fileURL.path) {
      do {
        try FileManager.default.removeItem(at: fileURL)
      } catch {
        logger.error("❌ Failed to remove offline page derivative \(fileURL.lastPathComponent): \(error)")
      }
    }
  }

  func refreshDownloadedBookSize(instanceId: String, bookId: String) async {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return }
    let bookDir = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId)
    guard let size = try? Self.calculateDirectorySize(bookDir) else { return }

    try? await DatabaseOperator.database().updateBookDownloadStatus(
      bookId: bookId,
      instanceId: instanceId,
      status: .downloaded,
      downloadedSize: size
    )
    await postDownloadProjectionDidChange(bookId: bookId, instanceId: instanceId)
  }

  func readOfflinePDFPreparationStamp(instanceId: String, bookId: String) async -> String? {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return nil }
    let file = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId).appendingPathComponent(
      Self.pdfPreparationStampFileName
    )
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    guard let data = try? Data(contentsOf: file) else { return nil }
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func writeOfflinePDFPreparationStamp(instanceId: String, bookId: String, stamp: String) async {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return }
    let file = bookDirectory(instanceId: instanceId, bookId: bookId).appendingPathComponent(
      Self.pdfPreparationStampFileName
    )
    guard let data = stamp.data(using: .utf8) else { return }
    do {
      try data.write(to: file)
      Self.excludeFromBackupIfNeeded(at: file)
    } catch {
      logger.error("❌ Failed to write PDF preparation stamp for book \(bookId): \(error)")
    }
  }

  func getOfflineEpubURL(instanceId: String, bookId: String) async -> URL? {
    guard await isBookDownloaded(bookId: bookId) else { return nil }
    let file = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId).appendingPathComponent(
      Self.epubFileName
    )
    return FileManager.default.fileExists(atPath: file.path) ? file : nil
  }

  func getOfflinePDFURL(instanceId: String, bookId: String) async -> URL? {
    guard await isBookDownloaded(bookId: bookId, instanceId: instanceId) else { return nil }
    let file = Self.bookDirectoryURL(instanceId: instanceId, bookId: bookId).appendingPathComponent(
      Self.pdfFileName
    )
    return FileManager.default.fileExists(atPath: file.path) ? file : nil
  }

  func prepareOfflineWebPubIfNeeded(instanceId: String, info: DownloadInfo) async throws -> Bool {
    guard await isBookDownloaded(bookId: info.bookId) else { return false }
    guard case .epubWebPub = info.kind else { return false }

    let bookDir = bookDirectory(instanceId: instanceId, bookId: info.bookId)
    guard let epubFile = existingEpubFileURL(in: bookDir) else { return false }

    var manifest = try? Self.readWebPubManifestSidecar(from: bookDir)
    if manifest == nil {
      manifest = try? await DatabaseOperator.database().fetchWebPubManifest(
        bookId: info.bookId,
        instanceId: instanceId
      )
    }
    guard let manifest else {
      throw AppErrorType.missingRequiredData(
        message: "Missing WebPub manifest for offline EPUB extraction."
      )
    }

    try Task.checkCancellation()
    do {
      try extractEpubToWebPub(
        epubFile: epubFile,
        bookId: info.bookId,
        manifest: manifest,
        bookDir: bookDir
      )
    } catch {
      let fileSize =
        (try? epubFile.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
      var magicHex = "unreadable"
      if let handle = try? FileHandle(forReadingFrom: epubFile) {
        if let head = try? handle.read(upToCount: 16), !head.isEmpty {
          magicHex = head.map { String(format: "%02x", $0) }.joined()
        }
        try? handle.close()
      }
      logger.error(
        "❌ EPUB WebPub extraction failed for book \(info.bookId), epubFile=\(epubFile.lastPathComponent), epubFileSize=\(fileSize), magic=\(magicHex), error=\(error.diagnosticDescription)"
      )
      await discardCorruptEpubIfUnreadable(
        epubFile: epubFile,
        bookId: info.bookId,
        instanceId: instanceId
      )
      throw error
    }
    try Task.checkCancellation()
    do {
      try FileManager.default.removeItem(at: epubFile)
    } catch {
      logger.warning("⚠️ Failed to remove prepared EPUB file for book \(info.bookId): \(error)")
    }

    await refreshDownloadedBookSize(instanceId: instanceId, bookId: info.bookId)
    return true
  }

  // MARK: - Resource Fetchers (Offline-Aware)

  func getBookPages(bookId: String) async throws -> [BookPage] {
    if let pages = try? await DatabaseOperator.database().fetchPages(id: bookId) {
      return pages
    }
    throw APIError.offline
  }

  func getBookTOC(bookId: String) async throws -> [ReaderTOCEntry] {
    if let toc = try? await DatabaseOperator.database().fetchTOC(id: bookId) {
      return toc
    }
    throw APIError.offline
  }

  func updateLocalProgress(bookId: String, page: Int, completed: Bool) async {
    try? await DatabaseOperator.database().updateReadingProgress(
      bookId: bookId, page: page, completed: completed)
  }

  private nonisolated static func calculateDirectorySize(_ url: URL) throws -> Int64 {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return 0
    }

    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let attrs = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
      // Only count files, not directories
      if attrs.isDirectory == false {
        total += Int64(attrs.fileSize ?? 0)
      }
    }
    return total
  }

  private nonisolated static func directoryContainsFiles(_ url: URL) -> Bool {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return false
    }

    for case let fileURL as URL in enumerator {
      let attrs = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
      if attrs?.isDirectory == false {
        return true
      }
    }

    return false
  }

  private nonisolated static func directoryContainsPageImages(_ url: URL) -> Bool {
    guard
      let fileURLs = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return false
    }

    return fileURLs.contains { fileURL in
      guard fileURL.lastPathComponent.hasPrefix("page-") else { return false }
      return (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
  }

  private static func writeArchivePagesSidecar(
    _ pages: [BookPage],
    to bookDir: URL
  ) throws {
    ensureDirectoryExists(at: bookDir)
    let fileURL = bookDir.appendingPathComponent(archivePagesFileName)
    let data = try JSONEncoder().encode(pages)
    try data.write(to: fileURL, options: [.atomic])
    excludeFromBackupIfNeeded(at: fileURL)
  }

  private static func readArchivePagesSidecar(from bookDir: URL) throws -> [BookPage] {
    let fileURL = bookDir.appendingPathComponent(archivePagesFileName)
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([BookPage].self, from: data)
  }

  private static func writeWebPubManifestSidecar(
    _ manifest: WebPubPublication,
    to bookDir: URL
  ) throws {
    ensureDirectoryExists(at: bookDir)
    let fileURL = bookDir.appendingPathComponent(webPubManifestFileName)
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: fileURL, options: [.atomic])
    excludeFromBackupIfNeeded(at: fileURL)
  }

  private static func readWebPubManifestSidecar(from bookDir: URL) throws -> WebPubPublication {
    let fileURL = bookDir.appendingPathComponent(webPubManifestFileName)
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode(WebPubPublication.self, from: data)
  }

  // MARK: - Private Helpers

  private func refreshQueueStatus(instanceId: String) async {
    let summary =
      (try? await DatabaseOperator.database().fetchDownloadQueueSummary(instanceId: instanceId))
      ?? .empty
    await MainActor.run {
      DownloadProgressTracker.shared.updateQueueStatus(
        pending: summary.pendingCount,
        failed: summary.failedCount
      )
    }
  }

  private func postDownloadProjectionDidChange(bookId: String, instanceId: String) async {
    await ContentProjectionNotifier.postBookAndSeriesDidChange(
      bookId: bookId,
      instanceId: instanceId,
      reason: .downloadStatus
    )
  }

  private func postDownloadProjectionsDidChange(bookIds: [String], instanceId: String) async {
    await ContentProjectionNotifier.postBooksAndSeriesDidChange(
      bookIds: bookIds,
      instanceId: instanceId,
      reason: .downloadStatus
    )
  }

  private func removeBookAfterPermanentNotFound(bookId: String, instanceId: String) async {
    #if os(iOS)
      await BackgroundDownloadManager.shared.cancelDownloads(forBookId: bookId)
      clearBackgroundDownloadContext(bookId: bookId)
    #endif

    removeActiveTask(bookId)
    removeOfflineFiles(instanceId: instanceId, bookId: bookId)
    try? await DatabaseOperator.database().deleteLocalBookAfterNotFound(
      bookId: bookId,
      instanceId: instanceId
    )
    await refreshQueueStatus(instanceId: instanceId)
  }

  private func removeOfflineFiles(instanceId: String, bookId: String) {
    removeBookDirectory(instanceId: instanceId, bookId: bookId)

    #if os(iOS) || os(macOS)
      SpotlightIndexService.removeBook(bookId: bookId, instanceId: instanceId)
    #endif
  }

  private func removeActiveTask(_ bookId: String) {
    activeTasks[bookId]?.cancel()
    activeTasks[bookId] = nil
    let isQueueEmpty = activeTasks.isEmpty
    logger.info("🧹 Cleared active task for book: \(bookId)")
    Task { @MainActor in
      DownloadProgressTracker.shared.clearProgress(bookId: bookId)
      if isQueueEmpty {
        DownloadProgressTracker.shared.finishDownload()
      }
    }
  }

  #if os(iOS)
    private func updateDownloadLiveActivityProgress(
      bookId: String,
      receivedBytes: Int64,
      expectedBytes: Int64?
    ) async {
      guard let expectedBytes, expectedBytes > 0 else { return }
      let progress = Double(receivedBytes) / Double(expectedBytes)
      await updateDownloadLiveActivityProgress(bookId: bookId, progress: progress)
    }

    private func updateDownloadLiveActivityProgress(
      bookId: String,
      progress: Double,
      bookInfoOverride: String? = nil
    ) async {
      let clampedProgress = min(max(progress, 0), 1)
      guard shouldUpdateLiveActivityProgress(bookId: bookId, progress: clampedProgress) else {
        return
      }

      let activityInfo: (instanceId: String, seriesTitle: String?, bookInfo: String)?
      if let entry = foregroundDownloadInfoByBookId[bookId] {
        activityInfo = (
          instanceId: entry.instanceId,
          seriesTitle: entry.info.seriesTitle,
          bookInfo: bookInfoOverride ?? entry.info.bookInfo
        )
      } else if let entry = backgroundDownloadInfo[bookId] {
        activityInfo = (
          instanceId: entry.instanceId,
          seriesTitle: entry.seriesTitle,
          bookInfo: bookInfoOverride ?? entry.bookInfo
        )
      } else {
        return
      }

      guard let activityInfo else { return }
      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(instanceId: activityInfo.instanceId))
        ?? []
      let failedCount =
        (try? await DatabaseOperator.database().fetchFailedBooksCount(
          instanceId: activityInfo.instanceId
        )) ?? 0
      await LiveActivityManager.shared.updateActivity(
        seriesTitle: activityInfo.seriesTitle,
        bookInfo: activityInfo.bookInfo,
        progress: clampedProgress,
        pendingCount: pendingBooks.count,
        failedCount: failedCount
      )
    }

    private func shouldUpdateLiveActivityProgress(bookId: String, progress: Double) -> Bool {
      let now = Date()
      let isTerminalValue = progress <= 0 || progress >= 1

      guard let snapshot = liveActivityProgressSnapshots[bookId] else {
        liveActivityProgressSnapshots[bookId] = (progress: progress, updatedAt: now)
        return true
      }

      let hasMeaningfulDelta = abs(snapshot.progress - progress) >= 0.01
      let isDue = now.timeIntervalSince(snapshot.updatedAt) >= 0.5
      guard isTerminalValue || hasMeaningfulDelta || isDue else {
        return false
      }

      liveActivityProgressSnapshots[bookId] = (progress: progress, updatedAt: now)
      return true
    }

    private func updateDownloadLiveActivityProcessing(
      bookId: String,
      instanceId: String,
      seriesTitle: String?,
      kind: DownloadContentKind
    ) async {
      liveActivityProgressSnapshots.removeValue(forKey: bookId)
      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(instanceId: instanceId)) ?? []
      let failedCount =
        (try? await DatabaseOperator.database().fetchFailedBooksCount(instanceId: instanceId))
        ?? 0
      await LiveActivityManager.shared.updateActivity(
        seriesTitle: seriesTitle,
        bookInfo: postDownloadTitle(for: kind),
        progress: 1.0,
        pendingCount: pendingBooks.count,
        failedCount: failedCount
      )
    }

    private func finishForegroundLiveActivity(bookId: String, instanceId: String) async {
      foregroundDownloadInfoByBookId.removeValue(forKey: bookId)
      liveActivityProgressSnapshots.removeValue(forKey: bookId)

      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(instanceId: instanceId)) ?? []
      let failedCount =
        (try? await DatabaseOperator.database().fetchFailedBooksCount(instanceId: instanceId))
        ?? 0

      if pendingBooks.isEmpty {
        if failedCount > 0 {
          await LiveActivityManager.shared.updateActivity(
            seriesTitle: String(localized: "Offline"),
            bookInfo: String(localized: "Download finished with failures"),
            progress: 1.0,
            pendingCount: 0,
            failedCount: failedCount
          )
        } else {
          await LiveActivityManager.shared.endActivity()
        }
        return
      }

      let candidate = foregroundDownloadInfoByBookId.values.first?.info
      let seriesTitle: String?
      let bookInfo: String
      if let candidate {
        seriesTitle = candidate.seriesTitle
        bookInfo = candidate.bookInfo
      } else {
        seriesTitle = String(localized: "Offline")
        bookInfo = String(localized: "Downloading")
      }
      await LiveActivityManager.shared.updateActivity(
        seriesTitle: seriesTitle,
        bookInfo: bookInfo,
        progress: candidate == nil ? 1.0 : 0.0,
        pendingCount: pendingBooks.count,
        failedCount: failedCount
      )
    }
  #endif

  /// Returns true when the server has confirmed the book no longer exists (HTTP 404).
  /// This happens when a file is replaced server-side and Komga issues a new book UUID,
  /// leaving the previously-cached UUID orphaned.
  private nonisolated func isPermanentNotFound(_ error: Error) -> Bool {
    if let apiError = error as? APIError, case .notFound = apiError {
      return true
    }
    return false
  }

  private nonisolated func isNetworkRelatedError(_ error: Error) -> Bool {
    if let apiError = error as? APIError {
      if case .networkError = apiError { return true }
      if case .offline = apiError { return true }
    }
    if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet,
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorResourceUnavailable:
        return true
      default:
        return false
      }
    }
    return false
  }

  private func shouldKeepPendingAfterNetworkFailure(_ error: Error) async -> Bool {
    guard isNetworkRelatedError(error) else { return false }
    if AppConfig.isOffline {
      return true
    }

    #if os(iOS)
      return await MainActor.run {
        UIApplication.shared.applicationState == .background
      }
    #else
      return false
    #endif
  }

  // MARK: - Background Download Handlers (iOS only)

  #if os(iOS)
    /// Track background download context per book
    private typealias BackgroundDownloadInfo = (
      instanceId: String,
      seriesTitle: String?,
      bookInfo: String,
      kind: DownloadContentKind
    )
    private var backgroundDownloadInfo: [String: BackgroundDownloadInfo] = [:]
    private var backgroundDownloadTotalTasks: [String: Int] = [:]
    private var backgroundDownloadCompletedTasks: [String: Int] = [:]
    private var backgroundDownloadFinalizingBooks: Set<String> = []
    private func handleBackgroundDownloadComplete(
      bookId: String, pageNumber: Int?, fileURL: URL
    ) async {
      let backgroundTaskId = await startBackgroundTask()
      defer {
        Task {
          await endBackgroundTask(backgroundTaskId)
        }
      }
      _ = pageNumber
      _ = fileURL

      guard let info = backgroundDownloadInfo[bookId],
        let totalTasks = backgroundDownloadTotalTasks[bookId],
        totalTasks > 0
      else {
        if (try? await DatabaseOperator.database().getDownloadStatus(bookId: bookId))
          == .downloaded
        {
          return
        }
        logger.debug("⏭️ Ignore completion callback without active context for book: \(bookId)")
        return
      }

      let completedTasks = min((backgroundDownloadCompletedTasks[bookId] ?? 0) + 1, totalTasks)
      backgroundDownloadCompletedTasks[bookId] = completedTasks
      let progress = Double(completedTasks) / Double(totalTasks)
      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(
          instanceId: info.instanceId
        )) ?? []
      let failedCount =
        (try? await DatabaseOperator.database().fetchFailedBooksCount(
          instanceId: info.instanceId
        )) ?? 0

      await MainActor.run {
        DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: progress)
      }

      await LiveActivityManager.shared.updateActivity(
        seriesTitle: info.seriesTitle,
        bookInfo: info.bookInfo,
        progress: progress,
        pendingCount: pendingBooks.count,
        failedCount: failedCount
      )

      if completedTasks >= totalTasks {
        await finalizeBackgroundDownloadIfReady(
          bookId: bookId,
          info: info,
          reason: "per-file completion"
        )
      }
    }

    private func handleBackgroundDownloadFailed(
      bookId: String, pageNumber: Int?, error: Error
    ) async {
      let backgroundTaskId = await startBackgroundTask()
      defer {
        Task {
          await endBackgroundTask(backgroundTaskId)
        }
      }
      _ = pageNumber

      guard let info = backgroundDownloadInfo[bookId] else {
        if (try? await DatabaseOperator.database().getDownloadStatus(bookId: bookId))
          == .downloaded
        {
          return
        }
        logger.warning(
          "⚠️ Missing background download context for failed task: \(bookId), recover queue from persisted state"
        )
        clearBackgroundDownloadContext(bookId: bookId)
        removeActiveTask(bookId)
        let instanceId = AppConfig.current.instanceId
        await refreshQueueStatus(instanceId: instanceId)
        await syncDownloadQueue(instanceId: instanceId)
        return
      }

      // Check if this is a network error while we're now offline
      let isNetworkError = isNetworkRelatedError(error)
      if isNetworkError && AppConfig.isOffline {
        // Network error caused offline mode switch - keep as pending for retry
        logger.info("⚠️ Background download paused due to network error: \(bookId)")
        return
      }

      if isPermanentNotFound(error) {
        logger.info("🧹 Book \(bookId) no longer exists on server; removing local record")
        await removeBookAfterPermanentNotFound(bookId: bookId, instanceId: info.instanceId)
        await syncDownloadQueue(instanceId: info.instanceId)
        return
      }

      // Mark book as failed
      logger.error("❌ Background download failed for \(bookId): \(error)")
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: bookId,
        instanceId: info.instanceId,
        status: .failed(error: error.diagnosticDescription)
      )
      await postDownloadProjectionDidChange(bookId: bookId, instanceId: info.instanceId)
      await refreshQueueStatus(instanceId: info.instanceId)

      // Cancel remaining downloads for this book
      await BackgroundDownloadManager.shared.cancelDownloads(forBookId: bookId)
      clearBackgroundDownloadContext(bookId: bookId)
      removeActiveTask(bookId)
      removeBookDirectoryIfEmpty(instanceId: info.instanceId, bookId: bookId)

      // Update Live Activity or end if no more pending
      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(
          instanceId: info.instanceId
        )) ?? []
      let failedCount =
        (try? await DatabaseOperator.database().fetchFailedBooksCount(
          instanceId: info.instanceId
        )) ?? 0

      if pendingBooks.isEmpty {
        if failedCount > 0 {
          // Keep showing if there are failures, update info to show summary
          await LiveActivityManager.shared.updateActivity(
            seriesTitle: String(localized: "Offline"),
            bookInfo: String(localized: "Download finished with failures"),
            progress: 1.0,
            pendingCount: 0,
            failedCount: failedCount
          )
        } else {
          await LiveActivityManager.shared.endActivity()
        }
      } else {
        await LiveActivityManager.shared.updateActivity(
          seriesTitle: info.seriesTitle,
          bookInfo: info.bookInfo,
          progress: 1.0,
          pendingCount: pendingBooks.count,
          failedCount: failedCount
        )
      }

      // Trigger next download
      await syncDownloadQueue(instanceId: info.instanceId)
    }

    private func handleAllBackgroundDownloadsComplete(bookId: String) async {
      let backgroundTaskId = await startBackgroundTask()
      defer {
        Task {
          await endBackgroundTask(backgroundTaskId)
        }
      }

      guard let info = backgroundDownloadInfo[bookId] else {
        if (try? await DatabaseOperator.database().getDownloadStatus(bookId: bookId))
          == .downloaded
        {
          return
        }
        logger.debug("⏭️ Ignore all-complete callback without active context for book: \(bookId)")
        return
      }

      await finalizeBackgroundDownloadIfReady(
        bookId: bookId,
        info: info,
        reason: "all-complete callback"
      )
    }

    private func finalizeBackgroundDownloadIfReady(
      bookId: String,
      info: BackgroundDownloadInfo,
      reason: String
    ) async {
      let totalTasks = backgroundDownloadTotalTasks[bookId] ?? 0
      let completedTasks = backgroundDownloadCompletedTasks[bookId] ?? 0
      if totalTasks > 0, completedTasks < totalTasks {
        logger.debug(
          "⏳ Defer \(reason): waiting per-file callbacks for book \(bookId), \(completedTasks)/\(totalTasks)"
        )
        return
      }

      if backgroundDownloadFinalizingBooks.contains(bookId) {
        logger.debug(
          "⏭️ Ignore duplicate \(reason) while finalizing book \(bookId), completed=\(completedTasks)/\(totalTasks)"
        )
        return
      }

      backgroundDownloadFinalizingBooks.insert(bookId)
      logger.debug(
        "🔒 Claimed background finalize from \(reason) for book \(bookId), completed=\(completedTasks)/\(totalTasks)"
      )
      await updateDownloadLiveActivityProcessing(
        bookId: bookId,
        instanceId: info.instanceId,
        seriesTitle: info.seriesTitle,
        kind: info.kind
      )
      await finalizeBackgroundBookDownload(bookId: bookId, info: info)
    }

    private func finalizeBackgroundBookDownload(
      bookId: String,
      info: BackgroundDownloadInfo
    ) async {
      defer {
        backgroundDownloadFinalizingBooks.remove(bookId)
      }
      logger.info("✅ Background downloads finished for book: \(bookId)")
      let bookDir = bookDirectory(instanceId: info.instanceId, bookId: bookId)

      let archiveFile = imageArchiveFileURL(for: info.kind, bookDir: bookDir)
      if let archiveFile, FileManager.default.fileExists(atPath: archiveFile.path) {
        let recoveryMessage = "Offline archive download is incomplete. Please retry downloading this book."

        func failArchiveValidation(_ message: String) async {
          logger.error("❌ \(message): \(bookId)")
          try? FileManager.default.removeItem(at: bookDir)
          try? await DatabaseOperator.database().updateBookDownloadStatus(
            bookId: bookId, instanceId: info.instanceId, status: .failed(error: message))
          await postDownloadProjectionDidChange(bookId: bookId, instanceId: info.instanceId)
          clearBackgroundDownloadContext(bookId: bookId)
          removeActiveTask(bookId)
          await refreshQueueStatus(instanceId: info.instanceId)
          await syncDownloadQueue(instanceId: info.instanceId)
        }

        do {
          try await finalizeExistingImageArchiveFile(
            info: DownloadInfo(
              bookId: bookId,
              seriesTitle: info.seriesTitle,
              bookInfo: info.bookInfo,
              kind: info.kind
            ),
            bookDir: bookDir
          )
        } catch {
          logger.error(
            "❌ Background archive validation failed for book \(bookId), file=\(archiveFile.lastPathComponent), bookDir=\(bookDir.path), error=\(String(describing: error))"
          )
          await failArchiveValidation(recoveryMessage)
          return
        }
      }

      // Validate EPUB downloads the same way image archives are validated: a
      // corrupt or non-archive file must fail the download here instead of
      // surfacing later as a reader error.
      let epubFile = bookDir.appendingPathComponent(Self.epubFileName)
      if FileManager.default.fileExists(atPath: epubFile.path) {
        switch info.kind {
        case .epubWebPub, .epubDivina:
          do {
            try await validateEpubArchiveFile(epubFile, bookId: bookId)
          } catch {
            let recoveryMessage =
              "Downloaded EPUB file is corrupt or unreadable. Please retry downloading this book."
            logger.error(
              "❌ Background EPUB validation failed for book \(bookId), bookDir=\(bookDir.path), error=\(error.diagnosticDescription)"
            )
            try? FileManager.default.removeItem(at: bookDir)
            try? await DatabaseOperator.database().updateBookDownloadStatus(
              bookId: bookId, instanceId: info.instanceId, status: .failed(error: recoveryMessage))
            await postDownloadProjectionDidChange(bookId: bookId, instanceId: info.instanceId)
            clearBackgroundDownloadContext(bookId: bookId)
            removeActiveTask(bookId)
            await refreshQueueStatus(instanceId: info.instanceId)
            await syncDownloadQueue(instanceId: info.instanceId)
            return
          }
        default:
          break
        }
      }

      // Keep EPUB files intact until the reader opens them and can show processing UI.
      if !FileManager.default.fileExists(atPath: epubFile.path),
        !hasCompletedOfflineResources(kind: info.kind, bookDir: bookDir)
      {
        switch info.kind {
        case .archiveImages, .epubWebPub, .epubDivina:
          let recoveryMessage: String
          switch info.kind {
          case .archiveImages:
            recoveryMessage = "Offline archive download is incomplete. Please retry downloading this book."
          default:
            recoveryMessage = "Offline EPUB download is incomplete. Please retry downloading this book."
          }
          logger.warning(
            "⚠️ Archive and extracted resources are both missing during background finalization for book \(bookId), bookDir=\(bookDir.path)"
          )
          try? await DatabaseOperator.database().updateBookDownloadStatus(
            bookId: bookId,
            instanceId: info.instanceId,
            status: .failed(error: recoveryMessage)
          )
          await postDownloadProjectionDidChange(bookId: bookId, instanceId: info.instanceId)
          clearBackgroundDownloadContext(bookId: bookId)
          removeActiveTask(bookId)
          removeBookDirectoryIfEmpty(instanceId: info.instanceId, bookId: bookId)
          await refreshQueueStatus(instanceId: info.instanceId)
          await syncDownloadQueue(instanceId: info.instanceId)
          return
        default:
          break
        }
      }

      await finalizeDownload(
        instanceId: info.instanceId,
        bookId: bookId,
        bookDir: bookDir
      )
      logger.info("✅ All background downloads complete for book: \(bookId)")

      clearBackgroundDownloadContext(bookId: bookId)

      let pendingBooks =
        (try? await DatabaseOperator.database().fetchPendingBooks(
          instanceId: info.instanceId
        )) ?? []
      if pendingBooks.isEmpty {
        let failedCount =
          (try? await DatabaseOperator.database().fetchFailedBooksCount(
            instanceId: info.instanceId
          )) ?? 0
        if failedCount > 0 {
          await LiveActivityManager.shared.updateActivity(
            seriesTitle: String(localized: "Offline"),
            bookInfo: String(localized: "Download finished with failures"),
            progress: 1.0,
            pendingCount: 0,
            failedCount: failedCount
          )
        } else {
          await LiveActivityManager.shared.endActivity()
        }
      }

      await syncDownloadQueue(instanceId: info.instanceId)
    }
  #endif

  // MARK: - Download Logic

  @discardableResult
  private func savePageMetadataFromServer(bookId: String, bookDir: URL? = nil) async throws
    -> [BookPage]
  {
    let pages = try await BookService.getBookPages(id: bookId)
    try? await DatabaseOperator.database().updateBookPages(bookId: bookId, pages: pages)
    if let bookDir {
      try Self.writeArchivePagesSidecar(pages, to: bookDir)
    }

    return pages
  }

  private func saveDivinaManifestTOCFromServerIfAvailable(bookId: String) async {
    if let manifest = try? await BookService.getBookManifest(id: bookId) {
      let toc = await ReaderManifestService(bookId: bookId).parseTOC(manifest: manifest)
      try? await DatabaseOperator.database().updateBookTOC(bookId: bookId, toc: toc)
    }
  }

  private func saveDivinaManifestTOC(
    bookId: String,
    manifest: DivinaManifest
  ) async {
    let toc = await ReaderManifestService(bookId: bookId).parseTOC(manifest: manifest)
    try? await DatabaseOperator.database().updateBookTOC(bookId: bookId, toc: toc)
  }

  private func downloadImageArchive(
    bookId: String,
    format: DownloadedImageArchiveFormat,
    to bookDir: URL
  ) async throws {
    let pages = try await savePageMetadataFromServer(bookId: bookId, bookDir: bookDir)

    await MainActor.run {
      DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 0.0)
    }

    let archiveFile = bookDir.appendingPathComponent(format.fileName)
    _ = try await BookService.downloadBookFile(bookId: bookId, to: archiveFile)
    Self.excludeFromBackupIfNeeded(at: archiveFile)

    await MainActor.run {
      DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 1.0)
    }
    #if os(iOS)
      await updateDownloadLiveActivityProgress(
        bookId: bookId,
        progress: 1.0,
        bookInfoOverride: String(localized: "Validating offline archive...")
      )
    #endif

    try Task.checkCancellation()
    try await validateImageArchiveFile(archiveFile: archiveFile, pages: pages)

    await MainActor.run {
      DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 1.0)
    }
    #if os(iOS)
      await updateDownloadLiveActivityProgress(bookId: bookId, progress: 1.0)
    #endif
  }

  private func downloadEpub(
    bookId: String,
    kind: DownloadContentKind,
    to bookDir: URL
  ) async throws {
    switch kind {
    case .epubWebPub:
      try await savePageMetadataFromServer(bookId: bookId, bookDir: bookDir)
      let webPubManifest = try await BookService.getBookWebPubManifest(bookId: bookId)
      try? await DatabaseOperator.database().updateBookWebPubManifest(
        bookId: bookId,
        manifest: webPubManifest
      )
      try Self.writeWebPubManifestSidecar(webPubManifest, to: bookDir)
    case .epubDivina:
      let manifest = try await BookService.getBookManifest(id: bookId)
      await saveDivinaManifestTOC(bookId: bookId, manifest: manifest)
      _ = try await savePageMetadataFromServer(bookId: bookId, bookDir: bookDir)
    default:
      return
    }

    await MainActor.run {
      DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 0.0)
    }

    let epubFile = bookDir.appendingPathComponent(Self.epubFileName)
    _ = try await BookService.downloadBookFile(bookId: bookId, to: epubFile)
    Self.excludeFromBackupIfNeeded(at: epubFile)
    try await validateEpubArchiveFile(epubFile, bookId: bookId)

    await MainActor.run {
      DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 1.0)
    }
    #if os(iOS)
      await updateDownloadLiveActivityProgress(bookId: bookId, progress: 1.0)
    #endif
  }

  private func finalizeExistingImageArchiveFile(
    info: DownloadInfo,
    bookDir: URL
  ) async throws {
    guard case .archiveImages(let format) = info.kind else { return }
    let archiveFile = bookDir.appendingPathComponent(format.fileName)
    var pages = (try? Self.readArchivePagesSidecar(from: bookDir)) ?? []
    if pages.isEmpty {
      pages = (try? await DatabaseOperator.database().fetchPages(id: info.bookId)) ?? []
    }
    guard !pages.isEmpty else {
      throw AppErrorType.missingRequiredData(
        message: "Missing page metadata for offline image archive validation."
      )
    }
    try await validateImageArchiveFile(archiveFile: archiveFile, pages: pages)
  }

  private func downloadPdfFile(bookId: String, to bookDir: URL) async throws {
    let fileURL = bookDir.appendingPathComponent(Self.pdfFileName)
    _ = try await BookService.downloadBookFile(bookId: bookId, to: fileURL)
    Self.excludeFromBackupIfNeeded(at: fileURL)
    await MainActor.run {
      DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 1.0)
    }
    #if os(iOS)
      await updateDownloadLiveActivityProgress(bookId: bookId, progress: 1.0)
    #endif
  }

  private func extractEpubToWebPub(
    epubFile: URL,
    bookId: String,
    manifest: WebPubPublication,
    bookDir: URL
  ) throws {
    let root = bookDir.appendingPathComponent("webpub", isDirectory: true)
    Self.ensureDirectoryExists(at: root)
    Self.excludeFromBackupIfNeeded(at: root)

    let resourceLinks = collectWebPubResourceLinks(from: manifest)
    let hrefs = Array(Set(resourceLinks))

    guard !hrefs.isEmpty else { return }

    // Komga already normalizes EPUB hrefs to publication resource keys.
    var archivePathToDestination: [String: URL] = [:]
    for href in hrefs {
      guard let archivePath = Self.manifestResourcePath(from: href),
        let normalizedArchivePath = Self.normalizeArchivePath(archivePath)
      else { continue }
      let destination = Self.webPubResourceURL(root: root, href: href)
      archivePathToDestination[normalizedArchivePath] = destination
    }

    let extracted = try ArchiveExtractionService.extractFiles(
      from: epubFile,
      destinationsByArchivePath: archivePathToDestination,
      normalizePath: Self.normalizeArchivePath
    )

    for file in extracted {
      Self.excludeFromBackupIfNeeded(at: file.destination.deletingLastPathComponent())
      Self.excludeFromBackupIfNeeded(at: file.destination)
    }
  }

  private func validateEpubArchiveFile(_ epubFile: URL, bookId: String) async throws {
    let paths = try await archivePathIndex(for: epubFile)
    guard !paths.isEmpty else {
      throw AppErrorType.dataCorrupted(
        message: "Downloaded EPUB archive has no readable entries."
      )
    }
  }

  /// Self-heal after a failed reader-open extraction: if the EPUB file itself
  /// is not a readable archive, the download is corrupt, so remove it and
  /// mark the book as failed — the next reader open re-downloads instead of
  /// failing again on the same file. Extraction failures with a readable
  /// archive (unsafe paths, disk full, ...) keep the file to avoid an
  /// endless re-download loop.
  private func discardCorruptEpubIfUnreadable(
    epubFile: URL,
    bookId: String,
    instanceId: String
  ) async {
    do {
      try await validateEpubArchiveFile(epubFile, bookId: bookId)
    } catch {
      logger.warning(
        "🧹 Removing corrupt EPUB and resetting download state for book \(bookId): \(error.diagnosticDescription)"
      )
      try? FileManager.default.removeItem(at: epubFile)
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: bookId,
        instanceId: instanceId,
        status: .failed(
          error: "Downloaded EPUB file is corrupt or unreadable. Please retry downloading this book."
        )
      )
      await postDownloadProjectionDidChange(bookId: bookId, instanceId: instanceId)
      await refreshQueueStatus(instanceId: instanceId)
    }
  }

  private func validateImageArchiveFile(
    archiveFile: URL,
    pages: [BookPage]
  ) async throws {
    guard !pages.isEmpty else {
      throw AppErrorType.missingRequiredData(
        message: "Book page metadata is empty for offline archive validation."
      )
    }

    let requiredPaths = try Self.requiredArchivePaths(for: pages)
    let availablePathsByNormalizedPath = try await archivePathIndex(for: archiveFile)
    let availablePaths = Set(availablePathsByNormalizedPath.keys)

    guard requiredPaths.isSubset(of: availablePaths) else {
      let missingPage = pages.first { page in
        guard let normalizedPath = Self.normalizeArchivePath(page.fileName) else { return true }
        return !availablePaths.contains(normalizedPath)
      }
      let missingPath = missingPage?.fileName ?? "unknown"
      throw AppErrorType.missingRequiredData(
        message: "Archive is missing page resource: \(missingPath)."
      )
    }
  }

  private func hasCompletedOfflineResources(kind: DownloadContentKind, bookDir: URL) -> Bool {
    switch kind {
    case .archiveImages:
      return existingImageArchiveFileURL(in: bookDir) != nil || Self.directoryContainsPageImages(bookDir)
    case .epubWebPub:
      return existingEpubFileURL(in: bookDir) != nil
        || Self.directoryContainsFiles(Self.webPubRootDirectoryURL(bookDir: bookDir))
    case .epubDivina:
      return existingEpubFileURL(in: bookDir) != nil || Self.directoryContainsPageImages(bookDir)
    default:
      return true
    }
  }

  private func imageArchiveFileURL(for kind: DownloadContentKind, bookDir: URL) -> URL? {
    guard case .archiveImages(let format) = kind else { return nil }
    return bookDir.appendingPathComponent(format.fileName)
  }

  private func existingEpubFileURL(in bookDir: URL) -> URL? {
    let file = bookDir.appendingPathComponent(Self.epubFileName)
    return FileManager.default.fileExists(atPath: file.path) ? file : nil
  }

  private func offlinePageImageFileURLs(bookDir: URL, page: BookPage) -> [URL] {
    let preferredExtension = page.detectedUTType?.preferredFilenameExtension?.lowercased() ?? "jpg"
    let fallbackExtension = (page.fileName as NSString).pathExtension.lowercased()
    let extensions =
      ([preferredExtension, fallbackExtension].filter { !$0.isEmpty } + ["png", "jpg"])
      .reduce(into: [String]()) { result, fileExtension in
        if !result.contains(fileExtension) {
          result.append(fileExtension)
        }
      }

    return extensions.map { fileExtension in
      bookDir.appendingPathComponent("page-\(page.number).\(fileExtension)")
    }
  }

  private func existingImageArchiveFileURL(in bookDir: URL) -> URL? {
    let formats: [DownloadedImageArchiveFormat] = [.cbz, .cbr]
    return
      formats
      .map { bookDir.appendingPathComponent($0.fileName) }
      .first { FileManager.default.fileExists(atPath: $0.path) }
  }

  private func existingArchivedPageSourceURL(in bookDir: URL) -> URL? {
    existingImageArchiveFileURL(in: bookDir) ?? existingEpubFileURL(in: bookDir)
  }

  private func pageImageCache(for instanceId: String) -> ImageCache {
    let key = instanceId.isEmpty ? "default" : instanceId
    if let cache = pageImageCachesByInstanceId[key] {
      return cache
    }

    let cache = ImageCache(instanceId: key)
    pageImageCachesByInstanceId[key] = cache
    return cache
  }

  private func archivePathIndex(
    for archiveFile: URL,
    priority: TaskPriority = .utility
  ) async throws -> [String: String] {
    let key = Self.archivePathIndexCacheKey(for: archiveFile)
    if let cachedIndex = archivePathIndexesByCacheKey[key] {
      return cachedIndex
    }

    let index = try await Task.detached(priority: priority) {
      try ArchiveExtractionService.regularArchivePaths(
        in: archiveFile,
        normalizePath: Self.normalizeArchivePath
      )
    }.value

    archivePathIndexesByCacheKey = archivePathIndexesByCacheKey.filter {
      $0.key.path != key.path
    }

    if archivePathIndexesByCacheKey.count >= Self.archivePathIndexCacheLimit,
      let evictedKey = archivePathIndexesByCacheKey.keys.first
    {
      archivePathIndexesByCacheKey.removeValue(forKey: evictedKey)
    }
    archivePathIndexesByCacheKey[key] = index
    return index
  }

  private func archivedPageData(from archiveFile: URL, page: BookPage) async throws -> Data {
    do {
      return try await Self.archiveEntryData(
        from: archiveFile,
        entryPath: page.fileName,
        priority: .userInitiated
      )
    } catch {
      guard let normalizedPath = Self.normalizeArchivePath(page.fileName) else {
        throw error
      }

      let archivePathIndex = try await archivePathIndex(
        for: archiveFile,
        priority: .userInitiated
      )
      guard let fallbackEntryPath = archivePathIndex[normalizedPath],
        fallbackEntryPath != page.fileName
      else {
        throw error
      }

      return try await Self.archiveEntryData(
        from: archiveFile,
        entryPath: fallbackEntryPath,
        priority: .userInitiated
      )
    }
  }

  private static func archiveEntryData(
    from archiveFile: URL,
    entryPath: String,
    priority: TaskPriority
  ) async throws -> Data {
    try await Task.detached(priority: priority) {
      try ArchiveExtractionService.fileData(
        from: archiveFile,
        entryPath: entryPath
      )
    }.value
  }

  private static func archivePathIndexCacheKey(for fileURL: URL) -> ArchivePathIndexCacheKey {
    let values = try? fileURL.resourceValues(forKeys: [
      .fileSizeKey,
      .contentModificationDateKey,
    ])

    return ArchivePathIndexCacheKey(
      path: fileURL.standardizedFileURL.path,
      fileSize: Int64(values?.fileSize ?? -1),
      modificationTime: values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1
    )
  }

  private static func requiredArchivePaths(for pages: [BookPage]) throws -> Set<String> {
    var requiredPaths: Set<String> = []
    for page in pages {
      guard let normalizedPath = normalizeArchivePath(page.fileName) else {
        throw AppErrorType.invalidFileURL(url: page.fileName)
      }
      requiredPaths.insert(normalizedPath)
    }
    return requiredPaths
  }

  private static func manifestResourcePath(from href: String) -> String? {
    let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var path = URLComponents(string: trimmed)?.path ?? trimmed
    if let range = path.range(of: "/resource/", options: .backwards) {
      path = String(path[range.upperBound...])
    }

    let withoutFragment = path.split(separator: "#", maxSplits: 1).first.map(String.init) ?? path
    let withoutQuery =
      withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
    let decodedPath = withoutQuery.removingPercentEncoding ?? withoutQuery
    return decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  private static func normalizeArchivePath(_ path: String) -> String? {
    // Komga's archive extractors may decode malformed path bytes as `?`, while
    // Swift can surface U+FFFD. Normalize that replacement marker before
    // comparing server page paths with local archive entries.
    let path = path.replacingOccurrences(of: "\u{FFFD}", with: "?")

    // Treat both `/` and `\` as separators. CBR archives created on Windows tooling
    // use backslashes inside entry paths, and Komga returns those verbatim in
    // `BookPage.fileName`. libarchive normalizes RAR `\` to `/` when extracting, so
    // matching the dictionary key and the staged relative path requires both sides
    // to canonicalize to the same form.
    let components =
      path
      .split(whereSeparator: { $0 == "/" || $0 == "\\" })
      .map(String.init)
    guard !components.isEmpty else { return nil }

    var normalized: [String] = []
    for component in components {
      switch component {
      case "", ".":
        continue
      case "..":
        guard !normalized.isEmpty else { return nil }
        normalized.removeLast()
      default:
        normalized.append(component)
      }
    }

    guard !normalized.isEmpty else { return nil }
    return normalized.joined(separator: "/")
  }

  private func collectWebPubResourceLinks(from manifest: WebPubPublication) -> [String] {
    let collections = [
      manifest.readingOrder,
      manifest.resources,
      manifest.images,
      manifest.links,
      manifest.pageList,
      manifest.toc,
      manifest.landmarks,
    ]

    return collections.flatMap { links in
      links.compactMap { link in
        guard let href = link.href, !href.isEmpty else { return nil }
        if link.templated == true { return nil }
        if href.hasPrefix("#") || href.hasPrefix("data:") { return nil }
        return href
      }
    }
  }

  private func downloadPages(instanceId: String, bookId: String, to bookDir: URL) async throws {
    let pages = try await savePageMetadataFromServer(bookId: bookId, bookDir: bookDir)
    await saveDivinaManifestTOCFromServerIfAvailable(bookId: bookId)

    var pagesToDownload: [BookPage] = []

    for page in pages {
      let ext = page.detectedUTType?.preferredFilenameExtension ?? "jpg"
      let destination = bookDir.appendingPathComponent("page-\(page.number).\(ext)")

      if FileManager.default.fileExists(atPath: destination.path) {
        continue
      }

      if await copyCachedPageIfAvailable(
        instanceId: instanceId,
        bookId: bookId,
        page: page,
        destination: destination
      ) {
        continue
      }

      pagesToDownload.append(page)
    }

    let total = Double(pages.count)
    var completedCount = pages.count - pagesToDownload.count
    if total > 0, completedCount > 0 {
      let progress = Double(completedCount) / total
      await MainActor.run {
        DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: progress)
      }
    }

    if pagesToDownload.isEmpty {
      await MainActor.run {
        DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: 1.0)
      }
      return
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      let maxConcurrent = 4
      var active = 0
      var iterator = pagesToDownload.makeIterator()

      func submitNext() {
        if let page = iterator.next() {
          let ext = page.detectedUTType?.preferredFilenameExtension ?? "jpg"
          group.addTask {
            try Task.checkCancellation()
            let fileName = "page-\(page.number).\(ext)"
            let dest = bookDir.appendingPathComponent(fileName)

            if !FileManager.default.fileExists(atPath: dest.path) {
              let (data, _) = try await BookService.getBookPage(
                bookId: bookId, page: page.number)
              try data.write(to: dest, options: [.atomic])
              Self.excludeFromBackupIfNeeded(at: dest)
            }
          }
          active += 1
        }
      }

      // Initial fill
      for _ in 0..<maxConcurrent {
        submitNext()
      }

      while active > 0 {
        try await group.next()
        active -= 1
        completedCount += 1

        let progress = Double(completedCount) / total

        // Update in-memory progress for UI
        await MainActor.run {
          DownloadProgressTracker.shared.updateProgress(bookId: bookId, value: progress)
        }

        submitNext()
      }
    }
  }

  private func copyCachedPageIfAvailable(
    instanceId: String,
    bookId: String,
    page: BookPage,
    destination: URL
  ) async -> Bool {
    if FileManager.default.fileExists(atPath: destination.path) {
      return true
    }

    let cache = pageImageCache(for: instanceId)
    guard await cache.hasImage(bookId: bookId, page: page) else {
      return false
    }

    let cachedURL = cache.imageFileURL(bookId: bookId, page: page)
    do {
      try FileManager.default.copyItem(at: cachedURL, to: destination)
      Self.excludeFromBackupIfNeeded(at: destination)
      return true
    } catch {
      logger.error("❌ Failed to copy cached page for book \(bookId) page \(page.number): \(error)")
      return false
    }
  }

  private func clearCachesAfterDownload(bookId: String, instanceId: String) async {
    await ImageCache.clearDiskCache(forBookId: bookId, instanceId: instanceId)
  }

  private func finalizeDownload(
    instanceId: String,
    bookId: String,
    bookDir: URL
  ) async {
    try? await DatabaseOperator.database().updateBookDownloadStatus(
      bookId: bookId,
      instanceId: instanceId,
      status: .downloaded,
      downloadAt: .now
    )
    await postDownloadProjectionDidChange(bookId: bookId, instanceId: instanceId)
    await refreshQueueStatus(instanceId: instanceId)
    await clearCachesAfterDownload(bookId: bookId, instanceId: instanceId)
    completedDownloadsSinceLastNotification += 1
    removeActiveTask(bookId)
    scheduleDownloadedSizeUpdate(instanceId: instanceId, bookId: bookId, bookDir: bookDir)

    #if os(iOS) || os(macOS)
      let compositeId = CompositeID.generate(instanceId: instanceId, id: bookId)
      if let book = try? await DatabaseOperator.database().fetchBook(id: compositeId) {
        SpotlightIndexService.indexBook(book, instanceId: instanceId)
      }
    #endif
  }

  private func scheduleDownloadedSizeUpdate(
    instanceId: String,
    bookId: String,
    bookDir: URL
  ) {
    Task.detached {
      guard let size = try? Self.calculateDirectorySize(bookDir) else { return }
      try? await DatabaseOperator.database().updateBookDownloadStatus(
        bookId: bookId,
        instanceId: instanceId,
        status: .downloaded,
        downloadedSize: size
      )
    }
  }

  // MARK: - File System Helpers

  private static func ensureDirectoryExists(at url: URL) {
    try? AppStorageDirectory.ensureDirectoryExists(at: url)
  }

  private static func excludeFromBackupIfNeeded(at url: URL) {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var target = url
    try? target.setResourceValues(values)
  }

  private static func migrateLegacyDirectoryIfNeeded(to destination: URL) {
    let legacy = legacyBaseDirectory()
    var legacyIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: legacy.path, isDirectory: &legacyIsDirectory),
      legacyIsDirectory.boolValue
    else {
      return
    }

    var destinationIsDirectory: ObjCBool = false
    let destinationExists = FileManager.default.fileExists(
      atPath: destination.path, isDirectory: &destinationIsDirectory)

    if !destinationExists {
      if (try? FileManager.default.moveItem(at: legacy, to: destination)) != nil {
        return
      }
    } else if destinationIsDirectory.boolValue, isDirectoryEmpty(at: destination) {
      do {
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: legacy, to: destination)
        return
      } catch {
        // Fall back to merge.
      }
    }

    mergeDirectoryContents(from: legacy, to: destination)
    if isDirectoryEmpty(at: legacy) {
      try? FileManager.default.removeItem(at: legacy)
    }
  }

  private static func legacyBaseDirectory() -> URL {
    let documentsDir =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return documentsDir.appendingPathComponent(directoryName, isDirectory: true)
  }

  private static func mergeDirectoryContents(from source: URL, to destination: URL) {
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: source,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }

    for item in items {
      let destinationURL = destination.appendingPathComponent(item.lastPathComponent)
      var sourceIsDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: item.path, isDirectory: &sourceIsDirectory)

      var destinationIsDirectory: ObjCBool = false
      let destinationExists = FileManager.default.fileExists(
        atPath: destinationURL.path, isDirectory: &destinationIsDirectory)

      if !destinationExists {
        try? FileManager.default.moveItem(at: item, to: destinationURL)
        excludeFromBackupIfNeeded(at: destinationURL)
        continue
      }

      if sourceIsDirectory.boolValue && destinationIsDirectory.boolValue {
        mergeDirectoryContents(from: item, to: destinationURL)
        if isDirectoryEmpty(at: item) {
          try? FileManager.default.removeItem(at: item)
        }
        continue
      }

      try? FileManager.default.removeItem(at: item)
    }
  }

  private static func isDirectoryEmpty(at url: URL) -> Bool {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
      return false
    }
    return contents.isEmpty
  }
}

// MARK: - Helper Extension

extension Book {
  var downloadInfo: DownloadInfo {
    let kind: DownloadContentKind
    if let archiveFormat = downloadedImageArchiveFormat {
      kind = .archiveImages(archiveFormat)
    } else if media.mediaProfileValue == .pdf {
      kind = .pdf
    } else if media.mediaProfileValue == .epub {
      kind = (media.epubDivinaCompatible ?? false) ? .epubDivina : .epubWebPub
    } else {
      kind = .pages
    }

    return DownloadInfo(
      bookId: id,
      seriesTitle: oneshot ? nil : seriesTitle,
      bookInfo: oneshot ? "\(metadata.title)" : "#\(metadata.number) - \(metadata.title)",
      kind: kind
    )
  }

  private var downloadedImageArchiveFormat: DownloadedImageArchiveFormat? {
    if let urlExtension = URL(string: url)?.pathExtension.lowercased() {
      return DownloadedImageArchiveFormat(fileExtension: urlExtension)
    }

    let mediaType = media.mediaType
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
}

private func postDownloadTitle(for kind: DownloadContentKind) -> String {
  switch kind {
  case .archiveImages:
    return String(localized: "Validating offline archive...")
  case .epubWebPub, .epubDivina:
    return String(localized: "Finalizing offline EPUB...")
  case .pdf:
    return String(localized: "Finalizing offline PDF...")
  case .pages:
    return String(localized: "Finalizing offline pages...")
  }
}
