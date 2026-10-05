//
// ThumbnailCache.swift
//
//

import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

extension Notification.Name {
  static let thumbnailDidRefresh = Notification.Name("thumbnailDidRefresh")
}

nonisolated enum ThumbnailType: String, CaseIterable, Hashable, Sendable {
  case book
  case series
  case collection
  case readlist
  case page

  var pathSegment: String {
    switch self {
    case .book: return "books"
    case .series: return "series"
    case .collection: return "collections"
    case .readlist: return "readlists"
    case .page: return "pages"
    }
  }
}

@globalActor
actor ThumbnailCache {
  static let shared = ThumbnailCache()

  private let logger = AppLogger(.cache)
  private let diskCacheURL: URL = CacheNamespace.directory(for: "KomgaThumbnailCache")
  private let fileManager = FileManager.default
  private var downloadTasks: [String: DownloadTaskEntry] = [:]
  private var imageTasks: [String: ImageTaskEntry] = [:]

  // Cached disk cache size (static for shared access)
  private static let cacheSizeActor = CacheSizeActor()
  private static let cleanupHighWatermarkPercent: Int64 = 90
  private static let cleanupTargetPercent: Int64 = 80
  private static let cleanupThrottleInterval: TimeInterval = 5

  private struct DiskCacheLimitReachedError: Error {}

  private struct DownloadTaskEntry {
    let id = UUID()
    let task: Task<URL, Error>
    let stopWhenCacheFull: Bool
  }

  private struct ImageTaskEntry {
    let id: UUID
    let task: Task<PlatformImage?, Never>
  }

  private static nonisolated func getMaxDiskCacheSize() -> Int {
    AppConfig.maxCoverCacheSize
  }

  private init() {}

  /// Get the local file URL for a thumbnail. The file may or may not exist.
  static nonisolated func getThumbnailFileURL(id: String, type: ThumbnailType, page: Int? = nil)
    -> URL
  {
    let directory = CacheNamespace.directory(for: "KomgaThumbnailCache")
    let typeDir = directory.appendingPathComponent(type.rawValue, isDirectory: true)

    let filename = page != nil ? "\(id)_\(page!).jpg" : "\(id).jpg"
    return typeDir.appendingPathComponent(filename)
  }

  /// Ensures the thumbnail exists locally, downloading it if necessary.
  /// For page thumbnails, will attempt to generate from offline downloaded pages first.
  /// Returns the local file:// URL.
  func ensureThumbnail(
    id: String,
    type: ThumbnailType,
    page: Int? = nil,
    force: Bool = false,
    refreshExpired: Bool = true,
    stopWhenCacheFull: Bool = false
  )
    async throws -> URL
  {
    let fileURL = Self.getThumbnailFileURL(id: id, type: type, page: page)
    let cacheNamespaceId = Self.currentCacheNamespaceId()

    if !force && fileManager.fileExists(atPath: fileURL.path) {
      guard refreshExpired else { return fileURL }
      return await cachedThumbnailOrRefreshedURL(id: id, type: type, page: page, fileURL: fileURL)
    }

    // For page thumbnails, try to generate from offline downloaded pages first
    if case .page = type, let pageNum = page {
      if let offlineURL = await generateThumbnailFromOfflinePage(
        bookId: id, pageNumber: pageNum, thumbnailURL: fileURL)
      {
        return offlineURL
      }
    }

    if stopWhenCacheFull, await Self.cacheSizeHasReachedMaxSize() {
      throw DiskCacheLimitReachedError()
    }

    let cacheKey = Self.taskCacheKey(
      id: id,
      type: type,
      page: page,
      force: force
    )
    if let existingEntry = downloadTasks[cacheKey] {
      do {
        return try await awaitDownloadTask(
          existingEntry.task,
          cancelOnCancellation: false
        )
      } catch {
        if shouldRetryStandardDownload(
          after: error,
          existingEntry: existingEntry,
          stopWhenCacheFull: stopWhenCacheFull
        ) {
          logger.debug(
            "↪️ Retrying standard thumbnail download for \(type.rawValue) \(id) after limited task ended"
          )
          removeDownloadTask(cacheKey: cacheKey, matching: existingEntry)
          return try await ensureThumbnail(
            id: id,
            type: type,
            page: page,
            force: force,
            refreshExpired: refreshExpired,
            stopWhenCacheFull: false
          )
        }
        throw error
      }
    }

    let task = Task<URL, Error> {
      let logSuffix = page != nil ? "page \(page!) of book \(id)" : "\(type.rawValue) \(id)"
      if force {
        logger.info("📡 Force refreshing thumbnail for \(logSuffix)")
      } else {
        logger.info("📡 Downloading thumbnail for \(logSuffix)")
      }

      // Ensure directory exists
      let typeDir = fileURL.deletingLastPathComponent()
      if !FileManager.default.fileExists(atPath: typeDir.path) {
        try FileManager.default.createDirectory(at: typeDir, withIntermediateDirectories: true)
      }

      let path: String
      if case .page = type, let pageNum = page {
        path = "/api/v1/books/\(id)/pages/\(pageNum)/thumbnail"
      } else {
        path = "/api/v1/\(type.pathSegment)/\(id)/thumbnail"
      }
      let (data, _, _) = try await APIClient.shared.requestData(path: path)
      let oldFileSize: Int64?
      if FileManager.default.fileExists(atPath: fileURL.path),
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
        let size = attributes[.size] as? Int64
      {
        oldFileSize = size
      } else {
        oldFileSize = nil
      }

      if stopWhenCacheFull,
        await Self.cacheSizeWouldExceedMaxSize(replacing: oldFileSize, with: Int64(data.count))
      {
        throw DiskCacheLimitReachedError()
      }

      let maxSize = Self.maxDiskCacheSizeBytes()
      let highWatermark = maxSize * Self.cleanupHighWatermarkPercent / 100
      let newFileSize = Int64(data.count)
      let (currentSize, _, isValid) = await Self.cacheSizeActor.get(
        namespace: cacheNamespaceId
      )

      func triggerCleanupIfNeeded() {
        Task.detached(priority: .utility) {
          await Self.cleanupDiskCacheIfNeeded()
        }
      }

      if !isValid {
        triggerCleanupIfNeeded()
      } else if let size = currentSize {
        let sizeAfterAdd = size - (oldFileSize ?? 0) + newFileSize
        if sizeAfterAdd > highWatermark {
          triggerCleanupIfNeeded()
        }
      }

      let fileExisted = FileManager.default.fileExists(atPath: fileURL.path)
      try data.write(to: fileURL, options: [.atomic])

      logger.info("✅ Saved thumbnail for \(type.rawValue) \(id)")

      await Self.cacheSizeActor.updateSize(
        delta: newFileSize - (oldFileSize ?? 0),
        namespace: cacheNamespaceId
      )
      if !fileExisted {
        await Self.cacheSizeActor.updateCount(delta: 1, namespace: cacheNamespaceId)
      }

      let (sizeAfterStore, _, isValidAfter) = await Self.cacheSizeActor.get(
        namespace: cacheNamespaceId
      )
      if isValidAfter, let size = sizeAfterStore, size > highWatermark {
        triggerCleanupIfNeeded()
      }

      if force {
        let memoryKey = ThumbnailMemoryCache.key(id: id, type: type, page: page)
        imageTasks[memoryKey] = nil
        await ThumbnailMemoryCache.shared.remove(forKey: memoryKey)
      }

      return fileURL
    }

    let entry = DownloadTaskEntry(task: task, stopWhenCacheFull: stopWhenCacheFull)
    downloadTasks[cacheKey] = entry

    do {
      let url = try await awaitDownloadTask(
        task,
        cancelOnCancellation: stopWhenCacheFull
      )
      removeDownloadTask(cacheKey: cacheKey, matching: entry)
      return url
    } catch {
      removeDownloadTask(cacheKey: cacheKey, matching: entry)
      if error is DiskCacheLimitReachedError {
        logger.debug("⏸️ Skipped thumbnail download for \(type.rawValue) \(id): cover cache is full")
      } else {
        logger.error(
          "❌ Failed to download thumbnail for \(type.rawValue) \(id): \(error.localizedDescription)")
      }
      throw error
    }
  }

  private nonisolated func awaitDownloadTask(
    _ task: Task<URL, Error>,
    cancelOnCancellation: Bool
  ) async throws -> URL {
    try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      if cancelOnCancellation {
        task.cancel()
      }
    }
  }

  // MARK: - Multi-level Image Access

  /// Decoded image for display, resolving memory → disk → network. This is the
  /// entry point for image consumers; file-level consumers (widgets, indexing,
  /// tint extraction) keep using `ensureThumbnail`.
  /// The memory tier holds covers only: page thumbnails stream through jump
  /// sheets by the hundreds and would churn the cover cache out.
  func image(id: String, type: ThumbnailType, page: Int? = nil) async -> PlatformImage? {
    let memoryKey = type != .page ? ThumbnailMemoryCache.key(id: id, type: type, page: page) : nil
    if let memoryKey, let cached = await ThumbnailMemoryCache.shared.image(forKey: memoryKey) {
      return cached
    }
    // Page thumbnails skip the memory tier, so they never join here either.
    guard let memoryKey else {
      return await loadImage(id: id, type: type, page: page)
    }
    // Cover loads join one in-flight task: cells recreated while a load is
    // running share it instead of decoding twice, and their cancellation
    // cannot abort the load.
    if let inFlight = imageTasks[memoryKey] {
      return await inFlight.task.value
    }
    let taskID = UUID()
    let task = Task<PlatformImage?, Never> {
      let decoded = await self.loadImage(id: id, type: type, page: page)
      // A force refresh or cache clear drops the registration; without the
      // check the stale decode would be written back over the fresh state.
      if let decoded, self.imageTasks[memoryKey]?.id == taskID {
        await ThumbnailMemoryCache.shared.store(decoded, forKey: memoryKey)
      }
      return decoded
    }
    imageTasks[memoryKey] = ImageTaskEntry(id: taskID, task: task)
    let loaded = await task.value
    imageTasks[memoryKey] = nil
    return loaded
  }

  private func loadImage(id: String, type: ThumbnailType, page: Int?) async -> PlatformImage? {
    guard let url = try? await ensureThumbnail(id: id, type: type, page: page) else {
      return nil
    }
    return await Task.detached(priority: .userInitiated) {
      guard let raw = PlatformImage(contentsOfFile: url.path) else { return nil }
      return await ImageDecodeHelper.decodeForDisplay(raw)
    }.value
  }

  /// Synchronous memory-tier lookup for view initializers; never touches disk.
  @MainActor static func cachedImage(id: String, type: ThumbnailType) -> PlatformImage? {
    ThumbnailMemoryCache.shared.image(forKey: ThumbnailMemoryCache.key(id: id, type: type))
  }

  private func shouldRetryStandardDownload(
    after error: Error,
    existingEntry: DownloadTaskEntry,
    stopWhenCacheFull: Bool
  ) -> Bool {
    guard !Task.isCancelled, !stopWhenCacheFull, existingEntry.stopWhenCacheFull else {
      return false
    }

    return error is DiskCacheLimitReachedError || error is CancellationError
  }

  private func removeDownloadTask(cacheKey: String, matching entry: DownloadTaskEntry) {
    guard downloadTasks[cacheKey]?.id == entry.id else { return }
    downloadTasks[cacheKey] = nil
  }

  /// Ensures a missing thumbnail exists without refreshing an already-cached file.
  /// This is intended for background offline cover sync where staleness does not matter.
  func ensureMissingThumbnail(id: String, type: ThumbnailType) async throws
    -> ThumbnailCacheMissingResult
  {
    let fileURL = Self.getThumbnailFileURL(id: id, type: type)
    if fileManager.fileExists(atPath: fileURL.path) {
      return .cached
    }

    do {
      _ = try await ensureThumbnail(
        id: id,
        type: type,
        force: false,
        refreshExpired: false,
        stopWhenCacheFull: true
      )
      await Self.postThumbnailDidRefresh(id: id, type: type)
      return .stored
    } catch is DiskCacheLimitReachedError {
      return .cacheLimitReached
    }
  }

  /// Returns cached cover thumbnail ids matching the requested ids.
  func cachedCoverThumbnailIds(matching requestedIdsByType: [ThumbnailType: Set<String>]) async
    -> [ThumbnailType: Set<String>]
  {
    let requestedIdsByType = requestedIdsByType.filter { type, ids in
      type != .page && !ids.isEmpty
    }
    guard !requestedIdsByType.isEmpty else { return [:] }

    let diskCacheURL = CacheNamespace.directory(for: "KomgaThumbnailCache")

    return await Task.detached(priority: .utility) {
      var cachedIdsByType: [ThumbnailType: Set<String>] = [:]
      let fileManager = FileManager.default

      for (type, requestedIds) in requestedIdsByType {
        let typeDirectory = diskCacheURL.appendingPathComponent(type.rawValue, isDirectory: true)
        guard
          let fileURLs = try? fileManager.contentsOfDirectory(
            at: typeDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
          )
        else {
          continue
        }

        var cachedIds = Set<String>()
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "jpg" {
          let isRegularFile =
            (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
          guard isRegularFile else { continue }

          let id = fileURL.deletingPathExtension().lastPathComponent
          if requestedIds.contains(id) {
            cachedIds.insert(id)
          }
        }

        if !cachedIds.isEmpty {
          cachedIdsByType[type] = cachedIds
        }
      }

      return cachedIdsByType
    }.value
  }

  private static nonisolated func taskCacheKey(
    id: String,
    type: ThumbnailType,
    page: Int?,
    force: Bool
  ) -> String {
    return page != nil
      ? "\(type.rawValue)#\(id)#\(page!)#\(force)"
      : "\(type.rawValue)#\(id)#\(force)"
  }

  private func cachedThumbnailOrRefreshedURL(
    id: String,
    type: ThumbnailType,
    page: Int?,
    fileURL: URL
  ) async -> URL {
    guard isExpiredThumbnail(fileURL) else { return fileURL }

    do {
      return try await ensureThumbnail(id: id, type: type, page: page, force: true)
    } catch {
      logExpiredThumbnailRefreshFailure(id: id, type: type, page: page, error: error)
      return fileURL
    }
  }

  private func isExpiredThumbnail(_ fileURL: URL) -> Bool {
    guard
      let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
      let modificationDate = attributes[.modificationDate] as? Date
    else {
      return false
    }

    return Date().timeIntervalSince(modificationDate) > AppConfig.coverCacheExpirationInterval
  }

  private func logExpiredThumbnailRefreshFailure(
    id: String,
    type: ThumbnailType,
    page: Int?,
    error: Error
  ) {
    let logSuffix = page != nil ? "page \(page!) of book \(id)" : "\(type.rawValue) \(id)"
    logger.debug(
      "⚠️ Failed to refresh expired thumbnail for \(logSuffix): \(error.localizedDescription)")
  }

  // MARK: - Offline Page Thumbnail Generation

  /// Generate thumbnail from offline downloaded page image
  /// - Parameters:
  ///   - bookId: The book ID
  ///   - pageNumber: The page number
  ///   - thumbnailURL: Destination URL for the generated thumbnail
  /// - Returns: URL of the generated thumbnail, or nil if generation failed
  private func generateThumbnailFromOfflinePage(
    bookId: String, pageNumber: Int, thumbnailURL: URL
  ) async -> URL? {
    let cacheNamespaceId = Self.currentCacheNamespaceId()

    // Check if book is downloaded offline
    guard await OfflineManager.shared.isBookDownloaded(bookId: bookId) else {
      return nil
    }

    let instanceId = AppConfig.current.instanceId

    // Try common image extensions
    let extensions = ["jpg", "jpeg", "png", "webp", "avif", "gif"]
    var offlinePageURL: URL?

    for ext in extensions {
      if let url = try? await OfflineManager.shared.getOfflinePageImageURL(
        instanceId: instanceId, bookId: bookId, pageNumber: pageNumber, fileExtension: ext)
      {
        offlinePageURL = url
        break
      }
    }

    guard let sourceURL = offlinePageURL else {
      logger.debug("⚠️ Offline page not found for book \(bookId) page \(pageNumber)")
      return nil
    }

    // Downsample the image to thumbnail size (300px max dimension, matching Komga API)
    guard let thumbnailData = downsampleImage(at: sourceURL, maxDimension: 300) else {
      logger.warning("⚠️ Failed to downsample offline page for book \(bookId) page \(pageNumber)")
      return nil
    }

    // Ensure directory exists
    let typeDir = thumbnailURL.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: typeDir.path) {
      try? fileManager.createDirectory(at: typeDir, withIntermediateDirectories: true)
    }

    do {
      let oldFileSize: Int64?
      if fileManager.fileExists(atPath: thumbnailURL.path),
        let attributes = try? fileManager.attributesOfItem(atPath: thumbnailURL.path),
        let size = attributes[.size] as? Int64
      {
        oldFileSize = size
      } else {
        oldFileSize = nil
      }

      let maxSize = Int64(Self.getMaxDiskCacheSize()) * 1024 * 1024
      let highWatermark = maxSize * Self.cleanupHighWatermarkPercent / 100
      let newFileSize = Int64(thumbnailData.count)
      let (currentSize, _, isValid) = await Self.cacheSizeActor.get(
        namespace: cacheNamespaceId
      )

      func triggerCleanupIfNeeded() {
        Task.detached(priority: .utility) {
          await Self.cleanupDiskCacheIfNeeded()
        }
      }

      if !isValid {
        triggerCleanupIfNeeded()
      } else if let size = currentSize {
        let sizeAfterAdd = size - (oldFileSize ?? 0) + newFileSize
        if sizeAfterAdd > highWatermark {
          triggerCleanupIfNeeded()
        }
      }

      let fileExisted = fileManager.fileExists(atPath: thumbnailURL.path)
      try thumbnailData.write(to: thumbnailURL, options: [.atomic])
      logger.info("✅ Generated thumbnail from offline page for book \(bookId) page \(pageNumber)")

      await Self.cacheSizeActor.updateSize(
        delta: newFileSize - (oldFileSize ?? 0),
        namespace: cacheNamespaceId
      )
      if !fileExisted {
        await Self.cacheSizeActor.updateCount(delta: 1, namespace: cacheNamespaceId)
      }

      let (sizeAfterStore, _, isValidAfter) = await Self.cacheSizeActor.get(
        namespace: cacheNamespaceId
      )
      if isValidAfter, let size = sizeAfterStore, size > highWatermark {
        triggerCleanupIfNeeded()
      }

      return thumbnailURL
    } catch {
      logger.error(
        "❌ Failed to save generated thumbnail for book \(bookId) page \(pageNumber): \(error)")
      return nil
    }
  }

  /// Downsample an image efficiently using ImageIO
  /// - Parameters:
  ///   - url: Source image URL
  ///   - maxDimension: Maximum width or height in pixels
  /// - Returns: JPEG data of the downsampled image, or nil if failed
  private nonisolated func downsampleImage(at url: URL, maxDimension: CGFloat) -> Data? {
    let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
      return nil
    }

    let downsampleOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
      ] as CFDictionary

    guard
      let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions)
    else {
      return nil
    }

    // Convert to JPEG data
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil)
    else {
      return nil
    }
    CGImageDestinationAddImage(destination, downsampledImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }

    return data as Data
  }

  // MARK: - Cache Management

  /// Clear disk cache for the current instance only
  static func clearCurrentInstanceDiskCache() async {
    await ThumbnailMemoryCache.shared.removeAll()
    await shared.clearImageTasks()
    let fileManager = FileManager.default
    let cacheNamespaceId = currentCacheNamespaceId()
    let diskCacheURL = await namespacedDiskCacheURL(namespaceId: cacheNamespaceId)

    await Task.detached(priority: .userInitiated) {
      try? fileManager.removeItem(at: diskCacheURL)
      try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }.value

    await cacheSizeActor.set(size: 0, count: 0, namespace: cacheNamespaceId)
  }

  /// Clear all disk cache for thumbnails
  static func clearAllDiskCache() async {
    await ThumbnailMemoryCache.shared.removeAll()
    await shared.clearImageTasks()
    let fileManager = FileManager.default
    let diskCacheURL = CacheNamespace.baseDirectory(for: "KomgaThumbnailCache")

    await Task.detached(priority: .userInitiated) {
      try? fileManager.removeItem(at: diskCacheURL)
      // Recreate the directory
      try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }.value

    // Reset cached size and count for every namespace.
    await cacheSizeActor.removeAll()
  }

  /// Drops in-flight cover loads so none can write back into a just-cleared tier.
  private func clearImageTasks() {
    imageTasks = [:]
  }

  /// Get disk cache size in bytes
  static func getDiskCacheSize() async -> Int64 {
    let (size, _, _) = await getDiskCacheInfo()
    return size
  }

  /// Get disk cache file count
  static func getDiskCacheCount() async -> Int {
    let (_, count, _) = await getDiskCacheInfo()
    return count
  }

  static func cacheSizeHasReachedMaxSize() async -> Bool {
    let (size, _, _) = await getDiskCacheInfo()
    return size >= maxDiskCacheSizeBytes()
  }

  /// Cleanup disk cache if needed
  static func cleanupDiskCacheIfNeeded() async {
    let fileManager = FileManager.default
    let cacheNamespaceId = currentCacheNamespaceId()
    let maxCacheSize = getMaxDiskCacheSize()
    let maxSize = Int64(maxCacheSize) * 1024 * 1024
    let highWatermark = maxSize * cleanupHighWatermarkPercent / 100
    let (cachedSize, _, isValid) = await cacheSizeActor.get(namespace: cacheNamespaceId)

    if isValid, let cachedSize, cachedSize <= highWatermark {
      return
    }

    guard
      await cacheSizeActor.tryBeginCleanup(
        minInterval: cleanupThrottleInterval,
        force: !isValid,
        namespace: cacheNamespaceId
      )
    else {
      return
    }

    let diskCacheURL = await namespacedDiskCacheURL(namespaceId: cacheNamespaceId)

    await Task.detached(priority: .utility) {
      await performDiskCacheCleanup(
        diskCacheURL: diskCacheURL,
        fileManager: fileManager,
        maxCacheSize: maxCacheSize,
        cacheNamespaceId: cacheNamespaceId
      )
    }.value

    await cacheSizeActor.endCleanup(namespace: cacheNamespaceId)
  }

  /// Refresh thumbnail by re-downloading from server
  /// - Parameters:
  ///   - id: The entity ID
  ///   - type: The thumbnail type
  static func refreshThumbnail(id: String, type: ThumbnailType) async throws {
    _ = try await shared.ensureThumbnail(id: id, type: type, force: true)

    await postThumbnailDidRefresh(id: id, type: type)
  }

  private static func postThumbnailDidRefresh(id: String, type: ThumbnailType) async {
    await MainActor.run {
      NotificationCenter.default.post(
        name: .thumbnailDidRefresh,
        object: nil,
        userInfo: ["id": id, "type": type.rawValue]
      )
    }
  }

  // MARK: - Private Management Helpers

  private static nonisolated func maxDiskCacheSizeBytes() -> Int64 {
    Int64(getMaxDiskCacheSize()) * 1024 * 1024
  }

  private static func cacheSizeWouldExceedMaxSize(
    replacing oldFileSize: Int64?,
    with newFileSize: Int64
  ) async -> Bool {
    let (currentSize, _, _) = await getDiskCacheInfo()
    let sizeAfterStore = currentSize - (oldFileSize ?? 0) + newFileSize
    return sizeAfterStore > maxDiskCacheSizeBytes()
  }

  private static func getDiskCacheInfo() async -> (size: Int64, count: Int, isValid: Bool) {
    let cacheNamespaceId = currentCacheNamespaceId()
    let cacheInfo = await cacheSizeActor.get(namespace: cacheNamespaceId)
    if cacheInfo.isValid, let size = cacheInfo.size, let count = cacheInfo.count {
      return (size, count, true)
    }

    let fileManager = FileManager.default
    let diskCacheURL = await namespacedDiskCacheURL(namespaceId: cacheNamespaceId)

    let result: (size: Int64, count: Int) = await Task.detached(priority: .utility) {
      guard fileManager.fileExists(atPath: diskCacheURL.path) else {
        return (0, 0)
      }

      let (_, fileInfo, totalSize) = collectFileInfo(
        at: diskCacheURL,
        fileManager: fileManager,
        includeDate: false
      )

      return (totalSize, fileInfo.count)
    }.value

    await cacheSizeActor.set(size: result.size, count: result.count, namespace: cacheNamespaceId)
    return (result.size, result.count, true)
  }

  nonisolated private static func currentCacheNamespaceId() -> String {
    CacheNamespace.identifier()
  }

  nonisolated private static func namespacedDiskCacheURL(namespaceId: String) async -> URL {
    CacheNamespace.directory(for: "KomgaThumbnailCache", instanceId: namespaceId)
  }

  private static func collectFileInfo(
    at diskCacheURL: URL,
    fileManager: FileManager,
    includeDate: Bool = false
  ) -> (files: [URL], fileInfo: [(url: URL, size: Int64, date: Date?)], totalSize: Int64) {
    let resourceKeys: [URLResourceKey] =
      includeDate
      ? [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
      : [.isDirectoryKey, .fileSizeKey]
    let resourceKeySet = Set(resourceKeys)

    guard
      let enumerator = fileManager.enumerator(
        at: diskCacheURL,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles]
      )
    else {
      return ([], [], 0)
    }

    var allFiles: [URL] = []
    var totalSize: Int64 = 0
    var fileInfo: [(url: URL, size: Int64, date: Date?)] = []

    for case let fileURL as URL in enumerator {
      guard
        let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeySet),
        resourceValues.isDirectory != true,
        let fileSize = resourceValues.fileSize
      else {
        continue
      }

      let size = Int64(fileSize)
      totalSize += size
      allFiles.append(fileURL)
      fileInfo.append((url: fileURL, size: size, date: resourceValues.contentModificationDate))
    }

    return (allFiles, fileInfo, totalSize)
  }

  private static func performDiskCacheCleanup(
    diskCacheURL: URL,
    fileManager: FileManager,
    maxCacheSize: Int,
    cacheNamespaceId: String
  ) async {
    let logger = AppLogger(.cache)
    let maxSize = Int64(maxCacheSize) * 1024 * 1024
    let highWatermark = maxSize * cleanupHighWatermarkPercent / 100
    let targetSize = maxSize * cleanupTargetPercent / 100
    let (_, fileInfo, totalSize) = collectFileInfo(
      at: diskCacheURL,
      fileManager: fileManager,
      includeDate: true
    )

    // Check validity state BEFORE deleting to decide strategy
    let (_, _, isValid) = await cacheSizeActor.get(namespace: cacheNamespaceId)

    if totalSize > highWatermark {
      logger.debug(
        "🧹 [CoverCache] Cleanup start: total=\(totalSize)B high=\(highWatermark)B target=\(targetSize)B files=\(fileInfo.count)"
      )

      let oldestFirst = fileInfo.sorted {
        ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast)
      }
      var currentSize = totalSize
      var bytesDeleted: Int64 = 0
      var filesDeleted = 0

      for info in oldestFirst {
        if currentSize <= targetSize { break }

        do {
          try fileManager.removeItem(at: info.url)
          bytesDeleted += info.size
          filesDeleted += 1
          currentSize -= info.size
        } catch {
          // Failed to delete (maybe race condition or permission).
          // Do not update counts for this file.
        }
      }

      if isValid {
        await cacheSizeActor.updateSize(delta: -bytesDeleted, namespace: cacheNamespaceId)
        await cacheSizeActor.updateCount(delta: -filesDeleted, namespace: cacheNamespaceId)
      } else {
        // If invalid, we must set the absolute value.
        // We use our scanned values minus what WE deleted.
        await cacheSizeActor.set(
          size: totalSize - bytesDeleted,
          count: fileInfo.count - filesDeleted,
          namespace: cacheNamespaceId
        )
      }

      logger.debug(
        "🧹 [CoverCache] Cleanup end: deletedFiles=\(filesDeleted) freed=\(bytesDeleted)B remaining=\(max(0, totalSize - bytesDeleted))B"
      )
    } else {
      // scanned size is within limits.
      // IF cache was valid, we do NOTHING (to avoid overwriting concurrent writes).
      // IF cache was invalid, we set it (sync).
      if !isValid {
        await cacheSizeActor.set(size: totalSize, count: fileInfo.count, namespace: cacheNamespaceId)
      }
    }
  }
}
