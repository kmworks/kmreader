//
// BackgroundDownloadManager.swift
//
//

import Foundation
import OSLog

#if os(iOS) || os(macOS)

  /// Information about a download task, persisted to UserDefaults for session reconnection
  struct BackgroundDownloadTaskInfo: Codable {
    let bookId: String
    let instanceId: String
    let pageNumber: Int?  // nil for file/resource downloads
    let isEpub: Bool
    let destinationPath: String
  }

  /// Manages background downloads that continue when app is backgrounded
  final class BackgroundDownloadManager: NSObject {
    static let shared = BackgroundDownloadManager()

    private let logger = AppLogger(.offline)
    private let sessionIdentifier = "com.kmreader.offline.background"

    /// Completion handler provided by iOS when app is woken for background events
    var backgroundCompletionHandler: (() -> Void)?

    /// Track active download tasks by task identifier
    private var activeTasks: [Int: BackgroundDownloadTaskInfo] = [:]

    /// Callbacks for download completion
    var onDownloadComplete: ((String, Int?, URL) -> Void)?  // bookId, pageNumber?, fileURL
    var onDownloadFailed: ((String, Int?, Error) -> Void)?  // bookId, pageNumber?, error
    var onDownloadProgress: ((String, Int64, Int64?) -> Void)?  // bookId, received, expected
    var onAllDownloadsComplete: ((String) -> Void)?  // bookId

    private lazy var backgroundSession: URLSession = {
      let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
      config.isDiscretionary = false  // download immediately, not when optimal
      config.sessionSendsLaunchEvents = true  // wake app on completion
      config.allowsCellularAccess = true
      config.httpMaximumConnectionsPerHost = 3

      return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
      super.init()
      loadTaskInfo()
    }

    // MARK: - Public API

    /// Reconnect to the background session after app relaunch
    func reconnectSession() {
      // Accessing backgroundSession triggers the lazy initialization
      // which reconnects to the background session
      _ = backgroundSession
      logger.info("🔄 Reconnected to background session")
    }

    /// Start a background download for an EPUB file
    func downloadEpub(
      bookId: String,
      instanceId: String,
      url: URL,
      destinationPath: String
    ) {
      downloadFile(
        bookId: bookId,
        instanceId: instanceId,
        url: url,
        destinationPath: destinationPath,
        reportByteProgress: true
      )
    }

    /// Start a background download for any single file resource
    func downloadFile(
      bookId: String,
      instanceId: String,
      url: URL,
      destinationPath: String,
      reportByteProgress: Bool
    ) {
      startDownload(
        bookId: bookId,
        instanceId: instanceId,
        pageNumber: nil,
        url: url,
        destinationPath: destinationPath,
        reportByteProgress: reportByteProgress,
        logAsInfo: reportByteProgress
      )
    }

    /// Start a background download for a page image
    func downloadPage(
      bookId: String,
      instanceId: String,
      pageNumber: Int,
      url: URL,
      destinationPath: String
    ) {
      startDownload(
        bookId: bookId,
        instanceId: instanceId,
        pageNumber: pageNumber,
        url: url,
        destinationPath: destinationPath,
        reportByteProgress: false,
        logAsInfo: false
      )
    }

    private func startDownload(
      bookId: String,
      instanceId: String,
      pageNumber: Int?,
      url: URL,
      destinationPath: String,
      reportByteProgress: Bool,
      logAsInfo: Bool
    ) {
      var request = URLRequest(url: url)
      addAuthHeaders(to: &request)

      let task = backgroundSession.downloadTask(with: request)
      task.taskDescription = destinationPath
      let taskInfo = BackgroundDownloadTaskInfo(
        bookId: bookId,
        instanceId: instanceId,
        pageNumber: pageNumber,
        isEpub: reportByteProgress,
        destinationPath: destinationPath
      )

      activeTasks[task.taskIdentifier] = taskInfo
      saveTaskInfo()

      if logAsInfo {
        logger.info("⬇️ Starting background file download for book: \(bookId)")
      } else if let pageNumber {
        logger.debug("⬇️ Starting background page download: \(bookId) page \(pageNumber)")
      } else {
        logger.debug("⬇️ Starting background resource download for book: \(bookId)")
      }
      task.resume()
    }

    /// Cancel all downloads for a specific book
    func cancelDownloads(forBookId bookId: String) {
      backgroundSession.getAllTasks { [weak self] tasks in
        guard let self = self else { return }
        Task { @MainActor in
          for task in tasks {
            if let info = self.activeTasks[task.taskIdentifier], info.bookId == bookId {
              task.cancel()
              self.activeTasks.removeValue(forKey: task.taskIdentifier)
            }
          }
          self.saveTaskInfo()
          self.logger.info("⛔ Cancelled all background downloads for book: \(bookId)")
        }
      }
    }

    /// Cancel all active downloads
    func cancelAllDownloads() {
      backgroundSession.getAllTasks { [weak self] tasks in
        guard let self = self else { return }
        Task { @MainActor in
          for task in tasks {
            task.cancel()
          }
          self.activeTasks.removeAll()
          self.saveTaskInfo()
          self.logger.info("⛔ Cancelled all background downloads")
        }
      }
    }

    /// Check if there are active downloads for a book
    func hasActiveDownloads(forBookId bookId: String) -> Bool {
      activeTasks.values.contains { $0.bookId == bookId }
    }

    // MARK: - Private Helpers

    private func addAuthHeaders(to request: inout URLRequest) {
      // Send both credentials: the server prefers the session token while it
      // is valid (avoiding per-request API key authentication activity) and
      // falls back to the API key, which never expires. Password logins only
      // have the session token; an expired session fails the task (caught by
      // status validation) until the next foreground refresh.
      let sessionToken = AppConfig.current.sessionToken
      if !sessionToken.isEmpty {
        request.setValue(sessionToken, forHTTPHeaderField: "X-Auth-Token")
      }
      if AppConfig.current.authMethod == .apiKey, !AppConfig.current.authToken.isEmpty {
        request.setValue(AppConfig.current.authToken, forHTTPHeaderField: "X-API-Key")
      }
    }

    /// Map a non-2xx download response to an error instead of saving the body
    /// as the downloaded file.
    private nonisolated func httpStatusError(for task: URLSessionDownloadTask) -> Error? {
      guard let httpResponse = task.response as? HTTPURLResponse,
        !(200...299).contains(httpResponse.statusCode)
      else { return nil }
      let urlString = task.originalRequest?.url?.absoluteString ?? ""
      let code = httpResponse.statusCode
      let message = HTTPURLResponse.localizedString(forStatusCode: code)
      switch code {
      case 401:
        return APIError.unauthorized(url: urlString)
      case 403:
        return APIError.forbidden(message: message, url: urlString, response: nil, request: nil)
      case 404:
        return APIError.notFound(message: message, url: urlString, response: nil, request: nil)
      case 429:
        return APIError.tooManyRequests(
          message: message, url: urlString, response: nil, request: nil)
      case 500...599:
        return APIError.serverError(
          code: code, message: message, url: urlString, response: nil, request: nil)
      default:
        return APIError.httpError(
          code: code, message: message, url: urlString, response: nil, request: nil)
      }
    }

    private func saveTaskInfo() {
      let encoder = JSONEncoder()
      if let data = try? encoder.encode(activeTasks) {
        AppConfig.backgroundDownloadTasksData = data
      }
    }

    private func loadTaskInfo() {
      guard let data = AppConfig.backgroundDownloadTasksData,
        let tasks = try? JSONDecoder().decode([Int: BackgroundDownloadTaskInfo].self, from: data)
      else {
        return
      }
      activeTasks = tasks
      logger.info("📂 Loaded \(tasks.count) pending background download tasks")
    }

    nonisolated private func moveDownloadedFile(from location: URL, to destinationURL: URL)
      -> Error?
    {
      let destinationDir = destinationURL.deletingLastPathComponent()

      do {
        // Create directory if needed
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
          try FileManager.default.createDirectory(
            at: destinationDir, withIntermediateDirectories: true)
        }
        Self.excludeFromBackupIfNeeded(at: destinationDir)

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
          try FileManager.default.removeItem(at: destinationURL)
        }

        // Move downloaded file
        try FileManager.default.moveItem(at: location, to: destinationURL)
        Self.excludeFromBackupIfNeeded(at: destinationURL)
        return nil
      } catch {
        return error
      }
    }

    nonisolated private static func excludeFromBackupIfNeeded(at url: URL) {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var target = url
      try? target.setResourceValues(values)
    }

    /// Removes empty directories above `fileURL`, stopping at the app's support directory.
    nonisolated private static func pruneEmptyAncestorDirectories(of fileURL: URL) {
      guard let stopURL = try? AppStorageDirectory.supportDirectory() else { return }
      let fm = FileManager.default
      let stopPath = stopURL.standardizedFileURL.path
      var current = fileURL.deletingLastPathComponent().standardizedFileURL
      while current.path != stopPath, current.path.hasPrefix(stopPath + "/") {
        guard let contents = try? fm.contentsOfDirectory(atPath: current.path), contents.isEmpty
        else { return }
        try? fm.removeItem(at: current)
        current = current.deletingLastPathComponent()
      }
    }

    private func handleDownloadCompletion(
      taskIdentifier: Int,
      destinationURL: URL,
      moveError: Error?
    ) {
      guard let taskInfo = activeTasks[taskIdentifier] else {
        logger.warning("⚠️ Completed download for unknown task: \(taskIdentifier)")
        // The task is no longer tracked (cancelled or reset), so nothing will
        // consume the file: drop it and the shell that moveDownloadedFile created.
        try? FileManager.default.removeItem(at: destinationURL)
        Self.pruneEmptyAncestorDirectories(of: destinationURL)
        return
      }

      if let moveError {
        logger.error(
          "❌ Failed to move downloaded file: \(moveError.localizedDescription)")
        onDownloadFailed?(taskInfo.bookId, taskInfo.pageNumber, moveError)
      } else {
        if let pageNumber = taskInfo.pageNumber {
          logger.debug("✅ Background page download complete: \(taskInfo.bookId) page \(pageNumber)")
        } else if taskInfo.isEpub {
          logger.info("✅ Background file download complete: \(taskInfo.bookId)")
        } else {
          logger.debug("✅ Background resource download complete: \(taskInfo.bookId)")
        }
        onDownloadComplete?(taskInfo.bookId, taskInfo.pageNumber, destinationURL)
      }

      // Remove from active tasks
      activeTasks.removeValue(forKey: taskIdentifier)
      saveTaskInfo()

      // Check if all downloads for this book are complete
      if !hasActiveDownloads(forBookId: taskInfo.bookId) {
        onAllDownloadsComplete?(taskInfo.bookId)
      }
    }

    private func handleDownloadError(taskIdentifier: Int, error: Error) {
      guard let taskInfo = activeTasks[taskIdentifier] else {
        return
      }

      logger.error(
        "❌ Background download failed for \(taskInfo.bookId): \(error.localizedDescription)")

      onDownloadFailed?(taskInfo.bookId, taskInfo.pageNumber, error)

      activeTasks.removeValue(forKey: taskIdentifier)
      saveTaskInfo()
    }
  }

  // MARK: - URLSessionDownloadDelegate

  extension BackgroundDownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      // Reject error responses before accepting the body as the downloaded file.
      if let statusError = httpStatusError(for: downloadTask) {
        try? FileManager.default.removeItem(at: location)
        Task { @MainActor in
          self.handleDownloadError(
            taskIdentifier: downloadTask.taskIdentifier, error: statusError)
        }
        return
      }

      // Move the temp file before returning; iOS can purge it after this delegate finishes.
      guard let destinationPath = downloadTask.taskDescription, !destinationPath.isEmpty else {
        let error = AppErrorType.missingRequiredData(
          message: "Missing destination path for download task."
        )
        Task { @MainActor in
          self.handleDownloadCompletion(
            taskIdentifier: downloadTask.taskIdentifier,
            destinationURL: location,
            moveError: error
          )
        }
        return
      }

      let destinationURL = URL(fileURLWithPath: destinationPath)
      let moveError = moveDownloadedFile(from: location, to: destinationURL)

      Task { @MainActor in
        self.handleDownloadCompletion(
          taskIdentifier: downloadTask.taskIdentifier,
          destinationURL: destinationURL,
          moveError: moveError
        )
      }
    }

    nonisolated func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didCompleteWithError error: Error?
    ) {
      Task { @MainActor in
        if let error = error {
          self.handleDownloadError(taskIdentifier: task.taskIdentifier, error: error)
        }
      }
    }

    nonisolated func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      Task { @MainActor in
        guard let taskInfo = self.activeTasks[downloadTask.taskIdentifier] else { return }

        // Only update byte progress for single-file downloads.
        // Multi-file downloads are tracked by completed count in OfflineManager.
        if taskInfo.isEpub, totalBytesExpectedToWrite > 0 {
          let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
          DownloadProgressTracker.shared.updateProgress(bookId: taskInfo.bookId, value: progress)
          self.onDownloadProgress?(
            taskInfo.bookId,
            totalBytesWritten,
            totalBytesExpectedToWrite
          )
        }
      }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
      // Called when all background session events have been delivered
      Task { @MainActor in
        if let handler = self.backgroundCompletionHandler {
          handler()
          self.backgroundCompletionHandler = nil
          self.logger.info("✅ All background session events finished")
        }
      }
    }
  }

#endif
