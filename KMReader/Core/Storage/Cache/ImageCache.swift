//
// ImageCache.swift
//
//

import Foundation
import OSLog
import SwiftUI

/// Disk cache system for storing raw image data
/// Used to avoid re-downloading images.
actor ImageCache {
  // Logger for cache operations
  private let logger = AppLogger(.cache)

  // Disk cache
  private let diskCacheURL: URL
  private let fileManager = FileManager.default
  private static let cleanupHighWatermarkPercent: Int64 = 90
  private static let cleanupTargetPercent: Int64 = 80
  private static let cleanupThrottleInterval: TimeInterval = 5

  // Get max page cache size from AppConfig (with fallback to default)
  private static func getMaxPageCacheSize() -> Int {
    AppConfig.maxPageCacheSize
  }

  // Cached disk cache size (static for shared access)
  private static let cacheSizeActor = CacheSizeActor()

  init(instanceId: String? = nil) {
    // Setup disk cache directory scoped to the active server namespace
    if let instanceId {
      diskCacheURL = CacheNamespace.directory(for: "KomgaImageCache", instanceId: instanceId)
    } else {
      diskCacheURL = CacheNamespace.directory(for: "KomgaImageCache")
    }

    // Clean up old disk cache on init
    Task {
      await Self.cleanupDiskCacheIfNeeded()
    }
  }

  // MARK: - Public API

  /// Check if image exists in disk cache
  func hasImage(bookId: String, page: BookPage) -> Bool {
    guard !bookId.isEmpty else { return false }
    let fileURL = imageFileURL(bookId: bookId, page: page)
    return FileManager.default.fileExists(atPath: fileURL.path)
  }

  /// Get cached image URL (creates no directories, may not exist on disk)
  nonisolated func imageFileURL(bookId: String, page: BookPage) -> URL {
    diskCacheFileURL(bookId: bookId, page: page, ensureDirectory: false)
  }

  /// Store image data to disk cache
  func storeImageData(_ data: Data, bookId: String, page: BookPage) async {
    guard !bookId.isEmpty else { return }

    let fileURL = diskCacheFileURL(bookId: bookId, page: page, ensureDirectory: true)

    let oldFileSize: Int64?
    if fileManager.fileExists(atPath: fileURL.path),
      let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
      let size = attributes[.size] as? Int64
    {
      oldFileSize = size
    } else {
      oldFileSize = nil
    }

    // Check cache size before storing and trigger cleanup if needed
    let (currentSize, _, isValid) = await Self.cacheSizeActor.get()
    let maxCacheSize = Self.getMaxPageCacheSize()
    let maxSize = Int64(maxCacheSize) * 1024 * 1024 * 1024
    let highWatermark = maxSize * Self.cleanupHighWatermarkPercent / 100
    let newFileSize = Int64(data.count)

    // Helper to trigger cleanup asynchronously
    func triggerCleanupIfNeeded() {
      Task.detached(priority: .utility) {
        await Self.cleanupDiskCacheIfNeeded()
      }
    }

    // If cache size info is invalid or exceeds limit, trigger cleanup
    if !isValid {
      triggerCleanupIfNeeded()
    } else if let size = currentSize {
      // Check if current size (before adding new file) would exceed limit
      let sizeAfterAdd = size - (oldFileSize ?? 0) + newFileSize
      // Trigger cleanup if cache size exceeds 90% of max size to be more proactive
      if sizeAfterAdd > highWatermark {
        triggerCleanupIfNeeded()
      }
    }

    let fileExisted = fileManager.fileExists(atPath: fileURL.path)

    // Write data to disk cache
    do {
      // Atomic so a page image mapped for animated playback never sees the
      // file truncated in place (mmap of a truncated file raises SIGBUS).
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      // Log write failure
      let dataSize = ByteCountFormatter.string(
        fromByteCount: Int64(data.count), countStyle: .binary)
      logger.error(
        "❌ Failed to write image cache for bookId \(bookId) page \(page.number) (\(page.fileName)) (\(dataSize)): \(error)"
      )
      // If write fails, don't update cache size/count
      // This ensures cache state remains consistent
      return
    }

    // Update cached size and count (only if cache is valid, otherwise it will be recalculated on next get)
    await Self.cacheSizeActor.updateSize(delta: newFileSize - (oldFileSize ?? 0))
    if !fileExisted {
      // New file added
      await Self.cacheSizeActor.updateCount(delta: 1)
    }

    // Check again after storing to ensure we're within limits
    let (sizeAfterStore, _, isValidAfter) = await Self.cacheSizeActor.get()
    if isValidAfter, let size = sizeAfterStore, size > highWatermark {
      // Cache exceeded limit after storing, trigger immediate cleanup
      triggerCleanupIfNeeded()
    }
  }

  func clearDiskCache(forBookId bookId: String) {
    let bookCacheDir = diskCacheURL.appendingPathComponent(bookId, isDirectory: true)
    try? fileManager.removeItem(at: bookCacheDir)
    Task {
      await Self.cacheSizeActor.invalidate()
    }
  }

  /// Clear disk cache for a specific book (static method for use from anywhere)
  static func clearDiskCache(forBookId bookId: String) async {
    await clearDiskCache(forBookId: bookId, instanceId: CacheNamespace.identifier())
  }

  /// Clear disk cache for a specific book and instance.
  static func clearDiskCache(forBookId bookId: String, instanceId: String) async {
    let fileManager = FileManager.default
    let diskCacheURL = CacheNamespace.directory(for: "KomgaImageCache", instanceId: instanceId)
    let bookCacheDir = diskCacheURL.appendingPathComponent(bookId, isDirectory: true)

    await Task.detached(priority: .userInitiated) {
      try? fileManager.removeItem(at: bookCacheDir)
    }.value

    // Invalidate cache size
    await cacheSizeActor.invalidate()
  }

  /// Clear disk cache for the current instance only
  static func clearCurrentInstanceDiskCache() async {
    let fileManager = FileManager.default
    let diskCacheURL = await namespacedDiskCacheURL()

    await Task.detached(priority: .userInitiated) {
      try? fileManager.removeItem(at: diskCacheURL)
      try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }.value

    await cacheSizeActor.set(size: 0, count: 0)
  }

  /// Clear all disk cache (static method for use from anywhere)
  static func clearAllDiskCache() async {
    let fileManager = FileManager.default
    let diskCacheURL = CacheNamespace.baseDirectory(for: "KomgaImageCache")

    await Task.detached(priority: .userInitiated) {
      try? fileManager.removeItem(at: diskCacheURL)
      // Recreate the directory
      try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }.value

    // Reset cached size and count
    await cacheSizeActor.set(size: 0, count: 0)
  }

  /// Get disk cache size in bytes (static method for use from anywhere)
  /// Uses cached value if available, otherwise calculates and caches the result
  static func getDiskCacheSize() async -> Int64 {
    let (size, _, _) = await getDiskCacheInfo()
    return size
  }

  /// Get disk cache file count (static method for use from anywhere)
  /// Uses cached value if available, otherwise calculates and caches the result
  static func getDiskCacheCount() async -> Int {
    let (_, count, _) = await getDiskCacheInfo()
    return count
  }

  /// Cleanup disk cache if needed (static method for use from anywhere)
  /// Checks current cache size against configured max size and cleans up if needed
  static func cleanupDiskCacheIfNeeded() async {
    let maxCacheSize = getMaxPageCacheSize()
    let maxSize = Int64(maxCacheSize) * 1024 * 1024 * 1024
    let highWatermark = maxSize * cleanupHighWatermarkPercent / 100
    let (cachedSize, _, isValid) = await cacheSizeActor.get()

    if isValid, let cachedSize, cachedSize <= highWatermark {
      return
    }

    guard
      await cacheSizeActor.tryBeginCleanup(
        minInterval: cleanupThrottleInterval,
        force: !isValid
      )
    else {
      return
    }

    let diskCacheURL = await namespacedDiskCacheURL()

    await Task.detached(priority: .utility) {
      await performDiskCacheCleanup(
        diskCacheURL: diskCacheURL,
        maxCacheSize: maxCacheSize
      )
    }.value

    await cacheSizeActor.endCleanup()
  }

  /// Get disk cache info (size and count) - internal method
  private static func getDiskCacheInfo() async -> (size: Int64, count: Int, isValid: Bool) {
    // Check cache first
    let cacheInfo = await cacheSizeActor.get()

    if cacheInfo.isValid, let size = cacheInfo.size, let count = cacheInfo.count {
      return (size, count, true)
    }

    // Cache miss or invalid, calculate size and count
    let fileManager = FileManager.default
    let diskCacheURL = await namespacedDiskCacheURL()

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

    // Update cache
    await cacheSizeActor.set(size: result.size, count: result.count)

    return (result.size, result.count, true)
  }

  // MARK: - Private Methods

  /// Namespaced disk cache directory URL (static helper)
  nonisolated private static func namespacedDiskCacheURL() async -> URL {
    CacheNamespace.directory(for: "KomgaImageCache")
  }

  /// Collect file information (size and modification date) for all files
  static func collectFileInfo(
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

  /// Perform disk cache cleanup
  /// Uses high/low watermark strategy: trigger at 90%, clean down to 80%
  static func performDiskCacheCleanup(
    diskCacheURL: URL,
    maxCacheSize: Int
  ) async {
    let fileManager = FileManager.default
    let logger = AppLogger(.cache)
    let maxSize = Int64(maxCacheSize) * 1024 * 1024 * 1024
    let highWatermark = maxSize * cleanupHighWatermarkPercent / 100
    let targetSize = maxSize * cleanupTargetPercent / 100  // Clean down to 80% for buffer
    let (_, fileInfo, totalSize) = collectFileInfo(
      at: diskCacheURL,
      fileManager: fileManager,
      includeDate: true
    )

    // Check validity state BEFORE deleting to decide strategy
    let (_, _, isValid) = await cacheSizeActor.get()

    if totalSize > highWatermark {
      logger.debug(
        "🧹 [PageCache] Cleanup start: total=\(totalSize)B high=\(highWatermark)B target=\(targetSize)B files=\(fileInfo.count)"
      )

      // Sort by date (oldest first) and remove until under target
      let sortedFiles = fileInfo.sorted {
        ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast)
      }
      var currentSize = totalSize
      var bytesDeleted: Int64 = 0
      var filesDeleted = 0

      for file in sortedFiles {
        if currentSize <= targetSize {
          break
        }

        do {
          try fileManager.removeItem(at: file.url)
          bytesDeleted += file.size
          filesDeleted += 1
          currentSize -= file.size
        } catch {
          // Failed to delete (maybe race condition or permission).
          // Do not update counts for this file.
        }
      }

      if isValid {
        await cacheSizeActor.updateSize(delta: -bytesDeleted)
        await cacheSizeActor.updateCount(delta: -filesDeleted)
      } else {
        // If invalid, we must set the absolute value.
        // We use our scanned values minus what WE deleted.
        await cacheSizeActor.set(size: totalSize - bytesDeleted, count: fileInfo.count - filesDeleted)
      }

      logger.debug(
        "🧹 [PageCache] Cleanup end: deletedFiles=\(filesDeleted) freed=\(bytesDeleted)B remaining=\(max(0, totalSize - bytesDeleted))B"
      )
    } else {
      // scanned size is within limits.
      // IF cache was valid, we do NOTHING (to avoid overwriting concurrent writes).
      // IF cache was invalid, we set it (sync).
      if !isValid {
        await cacheSizeActor.set(size: totalSize, count: fileInfo.count)
      }
    }
  }

  nonisolated private func diskCacheFileURL(
    bookId: String,
    page: BookPage,
    ensureDirectory: Bool
  ) -> URL {
    // Use the instance's diskCacheURL which includes the namespace
    let diskCacheURL = self.diskCacheURL
    let bookCacheDir = diskCacheURL.appendingPathComponent(bookId, isDirectory: true)
    let pageDirectory =
      bookCacheDir
      .appendingPathComponent("page", isDirectory: true)
      .appendingPathComponent("\(page.number)", isDirectory: true)

    if ensureDirectory {
      try? FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
    }

    let sanitizedFileName = (page.fileName as NSString).lastPathComponent
    let resolvedFileName =
      sanitizedFileName.isEmpty ? "page-\(page.number)" : sanitizedFileName
    return pageDirectory.appendingPathComponent(resolvedFileName)
  }

}
