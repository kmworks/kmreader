//
// EpubReaderViewModel.swift
//
//

#if os(iOS) || os(macOS)
  import Foundation
  import Observation
  import SwiftUI
  #if os(iOS)
    import UIKit
  #elseif os(macOS)
    import AppKit
  #endif

  struct WebPubLocation: Equatable {
    let href: String
    let title: String?
    let progression: Double?
    let totalProgression: Double?
    let pageIndex: Int
    let pageCount: Int
  }

  struct WebPubPageLocation: Equatable {
    let href: String
    let title: String?
    let type: String?
    let chapterIndex: Int
    let pageIndex: Int
    let pageCount: Int
    let url: URL
  }

  enum LoadingStage: String {
    case idle
    case fetchingMetadata
    case downloading
    case finalizingOfflineDownload
    case preparingOfflineResources
    case preparingReader
    case paginating
  }

  @MainActor
  @Observable
  class EpubReaderViewModel {
    var isLoading = false
    var errorMessage: String?
    var loadingStage: LoadingStage = .idle
    var downloadProgress: Double = 0.0
    var downloadBytesReceived: Int64 = 0
    var downloadBytesExpected: Int64?

    var tableOfContents: [WebPubLink] = []
    var currentChapterIndex: Int = 0
    var currentPageIndex: Int = 0
    var targetChapterIndex: Int?
    var targetPageIndex: Int?
    var currentLocation: WebPubLocation?
    var resourceRootURL: URL?
    var mediaTypesByRelativePath: [String: String] = [:]
    var publicationLanguage: String?
    var publicationReadingProgression: WebPubReadingProgression?

    private var bookId: String = ""
    private var downloadInfo: DownloadInfo? = nil
    private var readingOrder: [WebPubLink] = []
    private var pageCountCache: [String: Int] = [:]
    private var chapterPageCounts: [Int: Int] = [:]
    private var chapterURLCache: [Int: URL] = [:]
    private var textLengthCache: [String: Int] = [:]
    private var chapterTextWeights: [Int: Int] = [:]
    private var totalTextWeight: Int = 0
    private var hasFullTextWeights = false
    private var tocTitleByHref: [String: String] = [:]
    private var maxProgressionByHref: [String: Float] = [:]
    private var positionsLoadTask: Task<[String: Float], Never>?
    private var textLengthTask: Task<Void, Never>?
    private var initialChapterIndex: Int?
    private var initialProgression: Double?
    /// When the remote progression fetch fails transiently and there is no local
    /// progression to restore from, the reader falls back to page 0. Submitting
    /// that fallback position would regress the server's progress, so all
    /// progression submissions are suppressed for the session.
    private var progressSubmissionSuppressed = false
    /// Page-based read progress from the book DTO. Komga reports page-based
    /// progress (written by KOReader/Kindle sync, paged readers, or the web UI)
    /// as an empty locator on the progression endpoint, so the page number is
    /// the only resume hint for EPUB books in that state.
    private var fallbackPageNumber: Int?
    private var downloadResumeTask: Task<Void, Never>?
    private var lastUpdateTime: Date = Date()
    private let updateThrottleInterval: TimeInterval = 2.0
    // Where the session started, kept as a chapter and page rather than a
    // global page: global pages shift as chapters get measured.
    private var sessionStartPosition: (chapterIndex: Int, pageIndex: Int)?
    private var progressRecordingGate = ReaderProgressRecordingGate(wasInProgress: false)
    private let logger = AppLogger(.reader)
    private var viewportSize: CGSize = .zero
    private var preferences: EpubThemePreferences = .init()
    private var theme: ReaderTheme = .lightSepia

    let incognito: Bool

    init(incognito: Bool) {
      self.incognito = incognito
    }

    func updateDownloadProgress(notification: Notification) {
      guard let progressKey = notification.userInfo?[DownloadProgressUserInfo.itemKey] as? String else { return }
      guard progressKey == self.bookId else { return }

      let expected = notification.userInfo?[DownloadProgressUserInfo.expectedKey] as? Int64
      let received = notification.userInfo?[DownloadProgressUserInfo.receivedKey] as? Int64 ?? 0

      if let expected, expected > 0 {
        updateDownloadProgress(
          Double(received) / Double(expected),
          receivedBytes: received,
          expectedBytes: expected
        )
      } else {
        updateDownloadProgress(0.0, receivedBytes: received, expectedBytes: expected)
      }
    }

    func applyPreferences(_ prefs: EpubThemePreferences, colorScheme: ColorScheme) {
      preferences = prefs
      theme = prefs.resolvedTheme(for: colorScheme)

      if !readingOrder.isEmpty, viewportSize.width > 0 {
        refreshChapterPageCounts(keepingCurrent: true)
      }
    }

    func updateViewport(size: CGSize) {
      let containerInsets = containerInsetsForLabels()
      let adjustedWidth = size.width - containerInsets.left - containerInsets.right
      let adjustedHeight = size.height - containerInsets.top - containerInsets.bottom
      let normalized = CGSize(width: floor(adjustedWidth), height: floor(adjustedHeight))
      guard normalized.width > 0, normalized.height > 0 else { return }
      guard normalized != viewportSize else { return }
      viewportSize = normalized

      if !readingOrder.isEmpty {
        refreshChapterPageCounts(keepingCurrent: true)
      }
    }

    func beginLoading() {
      isLoading = true
      errorMessage = nil
      loadingStage = .fetchingMetadata
      downloadProgress = 0.0
      downloadBytesReceived = 0
      downloadBytesExpected = nil
    }

    func load(book: Book) async {
      downloadInfo = book.downloadInfo
      progressRecordingGate = ReaderProgressRecordingGate(wasInProgress: book.isInProgress)
      let shouldResumeFromProgression = !book.isCompleted
      fallbackPageNumber = shouldResumeFromProgression ? book.readProgress?.page : nil
      await load(
        bookId: book.id,
        shouldResumeFromProgression: shouldResumeFromProgression
      )
    }

    private func load(
      bookId: String,
      shouldResumeFromProgression: Bool
    ) async {
      downloadResumeTask?.cancel()
      downloadResumeTask = nil

      self.bookId = bookId
      isLoading = true
      errorMessage = nil
      loadingStage = .fetchingMetadata
      downloadProgress = 0.0
      downloadBytesReceived = 0
      downloadBytesExpected = nil
      tableOfContents = []
      currentChapterIndex = 0
      currentPageIndex = 0
      targetChapterIndex = nil
      targetPageIndex = nil
      currentLocation = nil
      resourceRootURL = nil
      mediaTypesByRelativePath = [:]
      publicationLanguage = nil
      publicationReadingProgression = nil
      chapterPageCounts = [:]
      chapterURLCache = [:]
      textLengthCache = [:]
      chapterTextWeights = [:]
      totalTextWeight = 0
      hasFullTextWeights = false
      tocTitleByHref = [:]
      maxProgressionByHref = [:]
      positionsLoadTask?.cancel()
      positionsLoadTask = nil
      textLengthTask?.cancel()
      textLengthTask = nil
      initialChapterIndex = nil
      initialProgression = nil
      progressSubmissionSuppressed = false
      sessionStartPosition = nil

      do {
        logger.debug("WebPub load started for bookId=\(bookId)")

        let instanceId = AppConfig.current.instanceId
        guard let downloadInfo = downloadInfo else {
          throw AppErrorType.missingRequiredData(
            message: "Missing book metadata for offline download."
          )
        }
        try await ensureOfflineReady(downloadInfo: downloadInfo, instanceId: instanceId)
        loadingStage = .preparingOfflineResources
        _ = try await OfflineManager.shared.prepareOfflineWebPubIfNeeded(
          instanceId: instanceId,
          info: downloadInfo
        )
        loadingStage = .preparingReader

        guard
          let database = await DatabaseOperator.databaseIfConfigured(),
          let manifest = await database.fetchWebPubManifest(bookId: bookId)
        else {
          throw AppErrorType.unknown(message: offlineEpubRecoveryMessage())
        }
        logger.debug("WebPub manifest loaded from offline storage")
        publicationLanguage = manifest.metadata?.language
        publicationReadingProgression = manifest.metadata?.readingProgression

        guard
          let offlineRoot = await OfflineManager.shared.getOfflineWebPubRootURL(
            instanceId: instanceId,
            bookId: bookId
          )
        else {
          throw AppErrorType.unknown(message: offlineEpubRecoveryMessage())
        }

        downloadProgress = 1.0
        loadingStage = .preparingReader
        readingOrder = manifest.readingOrder
        tableOfContents = manifest.toc.isEmpty ? manifest.readingOrder : manifest.toc
        tocTitleByHref = buildTOCTitleMap(from: tableOfContents)

        resourceRootURL = offlineRoot
        mediaTypesByRelativePath = Self.mediaTypeMap(from: manifest)
        // Page count cache is memory-only, no file loading needed
        loadTextLengthCache()
        try await cacheChapterURLs()

        var savedProgression: R2Progression?
        if shouldResumeFromProgression, !incognito {
          var remoteFetchFailed = false
          if !AppConfig.isOffline {
            remoteFetchFailed = await syncRemoteProgressionToLocal(bookId: bookId)
          }
          savedProgression = await database.fetchBookEpubProgression(bookId: bookId)

          if savedProgression == nil,
            let fallbackPage = fallbackPageNumber,
            fallbackPage > 1
          {
            // Komga answers the progression GET with an empty locator whenever
            // the stored read progress is page-based (KOReader/Kindle sync,
            // paged readers, web UI). That is not "no progress": map the known
            // page to a locator via the positions endpoint so the EPUB reader
            // resumes there instead of falling back to the first page.
            savedProgression = await restoreProgressionFromServerPage(
              bookId: bookId,
              page: fallbackPage,
              database: database
            )
            if savedProgression == nil {
              // The server has progress but it could not be located; never let
              // this session upload the first-page fallback over it.
              progressSubmissionSuppressed = true
              logger.warning(
                "⚠️ [Progress/Epub] Server has page-based progress (page \(fallbackPage)) that could not be mapped to a locator; suppressing progress submission for this session: book=\(bookId)"
              )
            }
          } else if remoteFetchFailed && savedProgression == nil {
            progressSubmissionSuppressed = true
            logger.warning(
              "⚠️ [Progress/Epub] Remote progression fetch failed and no local progression exists; suppressing progress submission for this session: book=\(bookId)"
            )
          }
        }

        if let savedProgression {
          logger.debug(
            "Fetched saved progression: href=\(savedProgression.locator.href), progression=\(savedProgression.locator.locations?.progression ?? 0)"
          )
          if let chapterIndex = chapterIndexForHref(savedProgression.locator.href) {
            logger.debug("Matched progression to chapterIndex=\(chapterIndex)")
            initialChapterIndex = chapterIndex
            initialProgression = Double(savedProgression.locator.locations?.progression ?? 0)
          } else {
            logger.debug("Failed to match progression href to any chapter in readingOrder")
          }
        }

        refreshChapterPageCounts(keepingCurrent: false)
        refreshChapterTextWeights()

        if let chapterIndex = initialChapterIndex,
          chapterIndex >= 0,
          chapterIndex < readingOrder.count
        {
          let pageCount = chapterPageCounts[chapterIndex] ?? 1
          let progression = initialProgression ?? 0
          let pageIndex = max(0, min(pageCount - 1, Int(floor(Double(pageCount) * progression))))
          currentChapterIndex = chapterIndex
          currentPageIndex = pageIndex
          targetChapterIndex = chapterIndex
          targetPageIndex = pageIndex
        } else if !readingOrder.isEmpty {
          currentChapterIndex = 0
          currentPageIndex = 0
          targetChapterIndex = 0
          targetPageIndex = 0
        }

        updateLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)

        loadingStage = .idle
        isLoading = false
        logger.debug("WebPub load ready")

      } catch is CancellationError {
        logger.debug("WebPub load cancelled")
        let status = await OfflineManager.shared.getDownloadStatus(bookId: bookId)
        if case .pending = status {
          loadingStage = .downloading
          isLoading = true
          errorMessage = nil
          downloadResumeTask = Task { [weak self] in
            await self?.waitForDownloadAndReload(
              bookId: bookId,
              shouldResumeFromProgression: shouldResumeFromProgression
            )
          }
          return
        }

        loadingStage = .idle
        isLoading = false
      } catch {
        let message = error.diagnosticDescription
        errorMessage = message
        ErrorManager.shared.alert(error: error)
        loadingStage = .idle
        isLoading = false
        logger.error("WebPub load failed for book \(bookId): \(error.diagnosticDescription)")
      }
    }

    private static func mediaTypeMap(from manifest: WebPubPublication) -> [String: String] {
      var map: [String: String] = [:]

      func collect(_ links: [WebPubLink]) {
        for link in links {
          if let href = link.href {
            let normalized = normalizedHref(href)
            if let safePath = EpubResourceSafeRelativePath(normalized), let type = link.type {
              map[safePath] = type
            }
          }
          if let children = link.children {
            collect(children)
          }
        }
      }

      collect(manifest.readingOrder)
      collect(manifest.resources)
      collect(manifest.images)
      collect(manifest.links)
      collect(manifest.toc)
      collect(manifest.pageList)
      collect(manifest.landmarks)
      return map
    }

    private func ensureOfflineReady(
      downloadInfo: DownloadInfo,
      instanceId: String
    ) async throws {
      let status = await OfflineManager.shared.getDownloadStatus(bookId: downloadInfo.bookId)
      if case .downloaded = status {
        return
      }

      if AppConfig.isOffline {
        throw AppErrorType.networkUnavailable
      }

      loadingStage = .downloading
      updateDownloadProgress(0.0, receivedBytes: 0, expectedBytes: nil)

      switch status {
      case .notDownloaded, .failed, .pending:
        await OfflineManager.shared.downloadForReading(
          instanceId: instanceId,
          info: downloadInfo
        )
      case .downloaded:
        return
      }

      while true {
        if AppConfig.isOffline {
          throw AppErrorType.networkUnavailable
        }

        let currentStatus = await OfflineManager.shared.getDownloadStatus(bookId: bookId)
        switch currentStatus {
        case .downloaded:
          updateDownloadProgress(1.0)
          return
        case .failed(let error):
          throw AppErrorType.operationFailed(message: error)
        case .notDownloaded:
          throw AppErrorType.operationFailed(
            message: String(localized: "Download did not start. Please try again.")
          )
        case .pending:
          if let progress = DownloadProgressTracker.shared.progress[bookId] {
            updateDownloadProgress(progress)
            if progress >= 1 {
              updateLoadingStage(.finalizingOfflineDownload)
            }
          }
        }

        try await Task.sleep(for: .milliseconds(200))
      }
    }

    private func waitForDownloadAndReload(
      bookId: String,
      shouldResumeFromProgression: Bool
    ) async {
      while true {
        if AppConfig.isOffline {
          errorMessage = AppErrorType.networkUnavailable.localizedDescription
          loadingStage = .idle
          isLoading = false
          return
        }

        let status = await OfflineManager.shared.getDownloadStatus(bookId: bookId)
        switch status {
        case .downloaded:
          await load(
            bookId: bookId,
            shouldResumeFromProgression: shouldResumeFromProgression
          )
          return
        case .failed(let error):
          errorMessage = AppErrorType.operationFailed(message: error).localizedDescription
          loadingStage = .idle
          isLoading = false
          return
        case .notDownloaded:
          errorMessage =
            AppErrorType.operationFailed(
              message: String(localized: "Download did not start. Please try again.")
            ).localizedDescription
          loadingStage = .idle
          isLoading = false
          return
        case .pending:
          if let progress = DownloadProgressTracker.shared.progress[bookId] {
            updateDownloadProgress(progress)
            if progress >= 1 {
              updateLoadingStage(.finalizingOfflineDownload)
            }
          }
        }

        try? await Task.sleep(for: .milliseconds(300))
      }
    }

    private func updateDownloadProgress(
      _ progress: Double,
      receivedBytes: Int64? = nil,
      expectedBytes: Int64? = nil
    ) {
      let displayProgress = ReaderLoadingProgress.displayValue(for: progress)
      let progressChanged = downloadProgress != displayProgress
      if progressChanged {
        downloadProgress = displayProgress
      }
      if receivedBytes != nil || expectedBytes != nil {
        updateDownloadBytesIfNeeded(
          received: receivedBytes ?? downloadBytesReceived,
          expected: expectedBytes,
          progressChanged: progressChanged
        )
      }
    }

    private func updateLoadingStage(_ stage: LoadingStage) {
      guard loadingStage != stage else { return }
      loadingStage = stage
    }

    private func updateDownloadBytesIfNeeded(
      received: Int64,
      expected: Int64?,
      progressChanged: Bool
    ) {
      guard downloadBytesReceived != received || downloadBytesExpected != expected else { return }
      guard
        expected == nil || progressChanged || downloadBytesReceived == 0 || downloadBytesExpected != expected
      else { return }
      downloadBytesReceived = received
      downloadBytesExpected = expected
    }

    func goToNextPage() {
      guard !readingOrder.isEmpty else { return }
      let pageCount = chapterPageCount(at: currentChapterIndex) ?? 1
      if currentPageIndex + 1 < pageCount {
        setTarget(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex + 1)
      } else if currentChapterIndex + 1 < chapterCount {
        setTarget(chapterIndex: currentChapterIndex + 1, pageIndex: 0)
      }
    }

    func goToPreviousPage() {
      guard !readingOrder.isEmpty else { return }
      if currentPageIndex > 0 {
        setTarget(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex - 1)
      } else if currentChapterIndex > 0 {
        let previousChapterIndex = currentChapterIndex - 1
        targetChapterIndex = previousChapterIndex
        targetPageIndex = -1
      }
    }

    func goToChapter(link: WebPubLink) {
      guard let href = link.href, let chapterIndex = chapterIndexForHref(href) else { return }
      setTarget(chapterIndex: chapterIndex, pageIndex: 0)
    }

    func navigateToURL(_ url: URL) {
      // Extract possible hrefs from the URL
      let path = url.path
      let lastComponent = url.lastPathComponent

      // Split path into components and try matching progressively longer paths from the end
      let pathComponents = path.split(separator: "/").map(String.init)
      var possibleHrefs: [String] = [lastComponent]

      // Build paths from the end (e.g., "chapter1.xhtml", "OEBPS/chapter1.xhtml", "content/OEBPS/chapter1.xhtml")
      for i in (0..<pathComponents.count).reversed() {
        let subPath = pathComponents[i...].joined(separator: "/")
        if !possibleHrefs.contains(subPath) {
          possibleHrefs.append(subPath)
        }
      }

      // Also try the full path
      possibleHrefs.append(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))

      for href in possibleHrefs {
        if let chapterIndex = chapterIndexForHref(href) {
          setTarget(chapterIndex: chapterIndex, pageIndex: 0)
          return
        }
      }
    }

    func pageDidChange() {
      let chapterIndex = currentChapterIndex
      let pageIndex = currentPageIndex
      updateLocation(chapterIndex: chapterIndex, pageIndex: pageIndex)
      guard currentLocation != nil else {
        logger.debug("⏭️ [Progress/Epub] Skip capture: current location unavailable")
        return
      }

      guard !incognito else {
        logger.debug("⏭️ [Progress/Epub] Skip capture: incognito mode enabled")
        return
      }
      guard !bookId.isEmpty else {
        logger.warning("⚠️ [Progress/Epub] Skip capture: missing book ID")
        return
      }

      if sessionStartPosition == nil {
        sessionStartPosition = (chapterIndex, pageIndex)
      }
      guard isProgressRecordingEligible(chapterIndex: chapterIndex, pageIndex: pageIndex) else {
        logger.debug(
          "⏭️ [Progress/Epub] Skip capture: below recording threshold, book=\(bookId), chapterIndex=\(chapterIndex), pageIndex=\(pageIndex)"
        )
        return
      }

      let now = Date()
      let elapsed = now.timeIntervalSince(lastUpdateTime)
      guard elapsed >= updateThrottleInterval else {
        logger.debug(
          String(
            format: "⏱️ [Progress/Epub] Skip capture due to throttle (elapsed=%.2fs, required=%.2fs)",
            elapsed,
            updateThrottleInterval
          )
        )
        return
      }
      lastUpdateTime = now
      progressRecordingGate.markRecorded()

      logger.debug(
        "📝 [Progress/Epub] Captured from page change: book=\(bookId), chapterIndex=\(chapterIndex), pageIndex=\(pageIndex)"
      )

      Task {
        await updateProgression(chapterIndex: chapterIndex, pageIndex: pageIndex)
      }
    }

    func flushProgress() {
      let chapterIndex = currentChapterIndex
      let pageIndex = currentPageIndex
      updateLocation(chapterIndex: chapterIndex, pageIndex: pageIndex)
      guard currentLocation != nil else {
        logger.debug("⏭️ [Progress/Epub] Skip flush: current location unavailable")
        return
      }
      guard !incognito else {
        logger.debug("⏭️ [Progress/Epub] Skip flush: incognito mode enabled")
        return
      }
      guard !bookId.isEmpty else {
        logger.warning("⚠️ [Progress/Epub] Skip flush: missing book ID")
        return
      }
      guard isProgressRecordingEligible(chapterIndex: chapterIndex, pageIndex: pageIndex) else {
        logger.debug(
          "⏭️ [Progress/Epub] Skip flush: below recording threshold, book=\(bookId), chapterIndex=\(chapterIndex), pageIndex=\(pageIndex)"
        )
        return
      }
      progressRecordingGate.markRecorded()

      let snapshotBookId = bookId
      logger.debug(
        "🚿 [Progress/Epub] Flush requested from EPUB reader: book=\(snapshotBookId), chapterIndex=\(chapterIndex), pageIndex=\(pageIndex)"
      )

      Task {
        await updateProgression(chapterIndex: chapterIndex, pageIndex: pageIndex)
      }
    }

    var chapterCount: Int {
      readingOrder.count
    }

    private func isProgressRecordingEligible(chapterIndex: Int, pageIndex: Int) -> Bool {
      let reachedLastPage =
        lastPagePosition().map {
          chapterIndex >= $0.chapterIndex && pageIndex >= $0.pageIndex
        } ?? false
      // Both ends of the distance use the current chapter page counts.
      let start = sessionStartPosition ?? (chapterIndex, pageIndex)
      let distance = abs(
        (pageOffsetBeforeChapter(chapterIndex) + pageIndex)
          - (pageOffsetBeforeChapter(start.chapterIndex) + start.pageIndex)
      )
      let totalPages = totalPageCount()
      return progressRecordingGate.allowsRecording(
        distance: distance,
        completed: reachedLastPage,
        pageCount: totalPages > 0 ? totalPages : nil
      )
    }

    var hasContent: Bool {
      !readingOrder.isEmpty
    }

    func lastPagePosition() -> (chapterIndex: Int, pageIndex: Int)? {
      guard !readingOrder.isEmpty else { return nil }
      let lastChapterIndex = readingOrder.count - 1
      let pageCount = chapterPageCount(at: lastChapterIndex) ?? 1
      return (lastChapterIndex, max(0, pageCount - 1))
    }

    func syncEndProgression() {
      guard !incognito else {
        logger.debug("⏭️ [Progress/Epub] Skip end sync: incognito mode enabled")
        return
      }
      guard !bookId.isEmpty else {
        logger.warning("⚠️ [Progress/Epub] Skip end sync: missing book ID")
        return
      }
      guard !AppConfig.isOffline else {
        logger.debug("⏭️ [Progress/Epub] Skip end sync: app is offline")
        return
      }
      guard let lastPosition = lastPagePosition() else {
        logger.debug("⏭️ [Progress/Epub] Skip end sync: last page position unavailable")
        return
      }

      logger.debug(
        "🏁 [Progress/Epub] Trigger end sync: book=\(bookId), chapterIndex=\(lastPosition.chapterIndex), pageIndex=\(lastPosition.pageIndex)"
      )
      updateLocation(chapterIndex: lastPosition.chapterIndex, pageIndex: lastPosition.pageIndex)

      Task {
        guard let href = readingOrder[lastPosition.chapterIndex].href else { return }
        let overrideProgression = await maxProgressionOverride(for: href)
        guard let overrideProgression else {
          logger.debug(
            "⏭️ [Progress/Epub] Skip end sync: max progression override unavailable, href=\(href)"
          )
          return
        }
        logger.debug(
          "📤 [Progress/Epub] Submit end progression override: book=\(bookId), href=\(href), progression=\(overrideProgression)"
        )
        await updateProgression(
          chapterIndex: lastPosition.chapterIndex,
          pageIndex: lastPosition.pageIndex,
          chapterProgressOverride: Double(overrideProgression),
          totalProgressOverride: nil
        )
      }
    }

    func pageLocation(chapterIndex: Int, pageIndex: Int) -> WebPubPageLocation? {
      guard chapterIndex >= 0, chapterIndex < readingOrder.count else { return nil }
      let pageCount = max(1, chapterPageCounts[chapterIndex] ?? 1)
      guard pageIndex >= 0, pageIndex < pageCount else { return nil }
      guard let cachedURL = chapterURLCache[chapterIndex] else { return nil }

      let link = readingOrder[chapterIndex]
      guard let href = link.href else { return nil }
      let normalizedHref = Self.normalizedHref(href)
      let title = link.title ?? tocTitleByHref[normalizedHref]

      return WebPubPageLocation(
        href: href,
        title: title,
        type: link.type,
        chapterIndex: chapterIndex,
        pageIndex: pageIndex,
        pageCount: pageCount,
        url: cachedURL
      )
    }

    func chapterURL(at index: Int) -> URL? {
      chapterURLCache[index]
    }

    func chapterMediaType(at index: Int) -> String? {
      guard index >= 0, index < readingOrder.count else { return nil }
      return readingOrder[index].type
    }

    func chapterPageCount(at index: Int) -> Int? {
      chapterPageCounts[index]
    }

    var resolvedViewportSize: CGSize? {
      viewportSize.width > 0 && viewportSize.height > 0 ? viewportSize : nil
    }

    func initialProgression(for chapterIndex: Int) -> Double? {
      guard initialChapterIndex == chapterIndex else { return nil }
      return initialProgression
    }

    func updateChapterPageCount(_ pageCount: Int, for chapterIndex: Int) {
      guard chapterIndex >= 0, chapterIndex < readingOrder.count else { return }
      let normalizedCount = max(1, pageCount)
      if chapterPageCounts[chapterIndex] == normalizedCount { return }

      chapterPageCounts[chapterIndex] = normalizedCount

      if chapterIndex == initialChapterIndex, let progression = initialProgression {
        let pageIndex = max(0, min(normalizedCount - 1, Int(floor(Double(normalizedCount) * progression))))
        logger.debug(
          "Applying initial progression to chapterIndex=\(chapterIndex): pageIndex=\(pageIndex)/\(normalizedCount)")
        let wasSamePosition = currentChapterIndex == chapterIndex && currentPageIndex == pageIndex
        currentChapterIndex = chapterIndex
        currentPageIndex = pageIndex
        if wasSamePosition {
          if targetChapterIndex == chapterIndex && targetPageIndex == pageIndex {
            // Avoid keeping a no-op target that can cause a late snap-back.
            targetChapterIndex = nil
            targetPageIndex = nil
          }
        } else {
          targetChapterIndex = chapterIndex
          targetPageIndex = pageIndex
        }
        initialChapterIndex = nil
        initialProgression = nil
        // The reader only now reaches the saved position; the page it showed
        // before the chapter was measured is not where the session started.
        sessionStartPosition = nil
      }

      normalizeCurrentPosition(adjustPageCount: false)
      normalizeTargetPosition(adjustPageCount: false)
      updateLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)

      // Store in memory cache only (no file persistence)
      let effectiveViewport = viewportSize.width > 0 ? viewportSize : Self.defaultViewportSize
      guard let href = readingOrder[chapterIndex].href else { return }
      let cacheKey = pageCountCacheKey(for: href, viewport: effectiveViewport)
      pageCountCache[cacheKey] = normalizedCount
    }

    var labelTopOffset: CGFloat {
      #if os(iOS)
        return PlatformHelper.isPad ? 24 : 8
      #else
        return 8
      #endif
    }
    var labelBottomOffset: CGFloat {
      #if os(iOS)
        return PlatformHelper.isPad ? 16 : 8
      #else
        return 8
      #endif
    }
    var useSafeArea: Bool {
      #if os(iOS)
        return !PlatformHelper.isPad
      #else
        return true
      #endif
    }

    func containerInsetsForLabels() -> ReaderContainerInsets {
      WebPubInfoOverlaySupport.containerInsets(
        topOffset: labelTopOffset,
        bottomOffset: labelBottomOffset
      )
    }

    // MARK: - Private Methods

    private func setTarget(chapterIndex: Int, pageIndex: Int) {
      guard !readingOrder.isEmpty else { return }
      let normalizedChapterIndex = max(0, min(chapterIndex, readingOrder.count - 1))
      let normalizedPageIndex = normalizedPageIndex(
        pageIndex,
        chapterIndex: normalizedChapterIndex,
        adjustPageCount: true
      )
      targetChapterIndex = normalizedChapterIndex
      targetPageIndex = normalizedPageIndex
    }

    private func normalizeCurrentPosition(adjustPageCount: Bool = true) {
      guard !readingOrder.isEmpty else {
        currentChapterIndex = 0
        currentPageIndex = 0
        return
      }
      let chapterIndex = max(0, min(currentChapterIndex, readingOrder.count - 1))
      let pageIndex = normalizedPageIndex(
        currentPageIndex,
        chapterIndex: chapterIndex,
        adjustPageCount: adjustPageCount
      )
      currentChapterIndex = chapterIndex
      currentPageIndex = pageIndex
    }

    private func normalizeTargetPosition(adjustPageCount: Bool = true) {
      guard let targetChapterIndex, let targetPageIndex else { return }
      guard !readingOrder.isEmpty else {
        self.targetChapterIndex = nil
        self.targetPageIndex = nil
        return
      }
      let chapterIndex = max(0, min(targetChapterIndex, readingOrder.count - 1))
      if targetPageIndex < 0 {
        self.targetChapterIndex = chapterIndex
        self.targetPageIndex = -1
        return
      }
      let pageIndex = normalizedPageIndex(
        targetPageIndex,
        chapterIndex: chapterIndex,
        adjustPageCount: adjustPageCount
      )
      self.targetChapterIndex = chapterIndex
      self.targetPageIndex = pageIndex
    }

    private func normalizedPageIndex(
      _ pageIndex: Int,
      chapterIndex: Int,
      adjustPageCount: Bool
    ) -> Int {
      let safeIndex = max(0, pageIndex)
      let storedCount = chapterPageCounts[chapterIndex] ?? 1
      let effectiveCount = adjustPageCount ? max(storedCount, safeIndex + 1) : storedCount
      if adjustPageCount, effectiveCount != storedCount {
        chapterPageCounts[chapterIndex] = effectiveCount
      }
      return min(safeIndex, effectiveCount - 1)
    }

    private func pageOffsetBeforeChapter(_ chapterIndex: Int) -> Int {
      guard chapterIndex > 0 else { return 0 }
      var offset = 0
      for idx in 0..<chapterIndex {
        offset += max(1, chapterPageCounts[idx] ?? 1)
      }
      return offset
    }

    private func totalPageCount() -> Int {
      guard !readingOrder.isEmpty else { return 0 }
      var total = 0
      for idx in 0..<readingOrder.count {
        total += max(1, chapterPageCounts[idx] ?? 1)
      }
      return total
    }

    private func buildTOCTitleMap(from links: [WebPubLink]) -> [String: String] {
      var map: [String: String] = [:]
      func collect(_ links: [WebPubLink]) {
        for link in links {
          if let href = link.href, let title = link.title, !title.isEmpty {
            map[Self.normalizedHref(href)] = title
          }
          if let children = link.children {
            collect(children)
          }
        }
      }
      collect(links)
      return map
    }

    private func updateLocation(chapterIndex: Int, pageIndex: Int) {
      guard let location = pageLocation(chapterIndex: chapterIndex, pageIndex: pageIndex) else {
        currentLocation = nil
        return
      }
      let chapterProgress =
        location.pageCount > 0
        ? Double(location.pageIndex + 1) / Double(location.pageCount)
        : nil
      let total =
        hasFullTextWeights
        ? totalProgression(location: location, chapterProgress: chapterProgress)
        : nil
      currentLocation = WebPubLocation(
        href: location.href,
        title: location.title,
        progression: chapterProgress,
        totalProgression: total,
        pageIndex: location.pageIndex,
        pageCount: location.pageCount
      )
    }

    func totalProgression(
      location: WebPubPageLocation,
      chapterProgress: Double?
    ) -> Double? {
      if hasFullTextWeights,
        let chapterWeight = chapterTextWeights[location.chapterIndex],
        totalTextWeight > 0,
        let chapterProgress
      {
        var beforeWeight = 0
        if location.chapterIndex > 0 {
          for idx in 0..<location.chapterIndex {
            beforeWeight += chapterTextWeights[idx] ?? 0
          }
        }
        let progressed = Double(beforeWeight) + (chapterProgress * Double(chapterWeight))
        return progressed / Double(totalTextWeight)
      }

      let totalPages = totalPageCount()
      guard totalPages > 0 else { return nil }
      let pageOffset = pageOffsetBeforeChapter(location.chapterIndex)
      let overallIndex = pageOffset + location.pageIndex
      return Double(overallIndex + 1) / Double(totalPages)
    }

    private func updateProgression(
      chapterIndex: Int,
      pageIndex: Int,
      chapterProgressOverride: Double? = nil,
      totalProgressOverride: Double? = nil
    ) async {
      guard !progressSubmissionSuppressed else {
        logger.warning(
          "⏭️ [Progress/Epub] Submission suppressed: position was not restored from a trusted source this session, book=\(bookId)"
        )
        return
      }
      guard let location = pageLocation(chapterIndex: chapterIndex, pageIndex: pageIndex) else { return }
      let chapterProgress =
        chapterProgressOverride
        ?? (location.pageCount > 0
          ? Double(location.pageIndex) / Double(location.pageCount)
          : nil)
      let totalProgressionValue =
        totalProgressOverride
        ?? totalProgression(
          location: location,
          chapterProgress: chapterProgress
        )
        ?? 0

      let totalProgression = Float(totalProgressionValue)
      let chapterProgression: Float? = chapterProgress.map(Float.init)

      let r2Location = R2Locator.Location(
        fragments: nil,
        progression: chapterProgression,
        position: nil,
        totalProgression: totalProgression
      )

      let locator = R2Locator(
        href: stripResourcePrefix(location.href),
        type: location.type ?? "text/html",
        title: location.title,
        locations: r2Location,
        text: nil,
        koboSpan: nil
      )

      let progression = R2Progression(
        modified: Date(),
        device: R2Device(
          id: AppConfig.deviceIdentifier,
          name: AppConfig.userAgent
        ),
        locator: locator
      )

      let activeBookId = bookId
      let logger = self.logger

      let progressionData: Data?
      if AppConfig.isOffline {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        progressionData = try? encoder.encode(progression)
      } else {
        progressionData = nil
      }

      logger.debug(
        "📝 [Progress/Epub] Prepared payload: book=\(activeBookId), href=\(locator.href), progression=\(locator.locations?.progression ?? 0), totalProgression=\(locator.locations?.totalProgression ?? 0), globalPage=\(pageOffsetBeforeChapter(chapterIndex) + pageIndex + 1), offline=\(AppConfig.isOffline)"
      )
      let pageOffset = pageOffsetBeforeChapter(chapterIndex)
      let globalPageNumber = pageOffset + pageIndex + 1

      logger.debug(
        "📮 [Progress/Epub] Submit to dispatch service: book=\(activeBookId), href=\(locator.href), globalPage=\(globalPageNumber)"
      )

      await ReaderProgressDispatchService.shared.submitEpubProgression(
        bookId: activeBookId,
        globalPageNumber: globalPageNumber,
        progression: progression,
        progressionData: progressionData
      )
    }

    private func refreshChapterPageCounts(keepingCurrent: Bool) {
      guard !readingOrder.isEmpty else { return }

      var effectiveViewport = viewportSize
      if effectiveViewport.width <= 0 {
        effectiveViewport = Self.defaultViewportSize
      }

      for (index, link) in readingOrder.enumerated() {
        let cacheKey = pageCountCacheKey(for: link.href ?? "", viewport: effectiveViewport)
        let cachedCount = pageCountCache[cacheKey]
        chapterPageCounts[index] = max(1, cachedCount ?? 1)
      }
      if keepingCurrent {
        normalizeCurrentPosition()
        normalizeTargetPosition()
      }
      updateLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)
    }

    private func refreshChapterTextWeights() {
      chapterTextWeights = [:]
      for (index, link) in readingOrder.enumerated() {
        let key = Self.normalizedHref(link.href ?? "")
        if let cached = textLengthCache[key] {
          chapterTextWeights[index] = max(1, cached)
        }
      }
      recomputeTextWeightState()
      computeMissingTextWeights()
    }

    private func recomputeTextWeightState() {
      totalTextWeight = chapterTextWeights.values.reduce(0, +)
      hasFullTextWeights = chapterTextWeights.count == readingOrder.count && totalTextWeight > 0
    }

    private func computeMissingTextWeights() {
      guard !readingOrder.isEmpty else { return }
      textLengthTask?.cancel()

      let readingOrder = self.readingOrder
      let chapterURLCache = self.chapterURLCache
      var localCache = textLengthCache

      textLengthTask = Task.detached(priority: .utility) { [weak self] in
        guard let self else { return }

        for (index, link) in readingOrder.enumerated() {
          if Task.isCancelled { return }
          let key = Self.normalizedHref(link.href ?? "")
          if localCache[key] != nil { continue }
          guard let url = chapterURLCache[index] else { continue }
          guard let data = try? Data(contentsOf: url) else { continue }
          let length = ReaderXHTMLParser.textLength(from: data, baseURL: url) ?? 0
          let normalizedLength = max(1, length)
          localCache[key] = normalizedLength

          await MainActor.run {
            self.textLengthCache[key] = normalizedLength
            self.chapterTextWeights[index] = normalizedLength
            self.recomputeTextWeightState()
            self.saveTextLengthCache()
            self.updateLocation(chapterIndex: self.currentChapterIndex, pageIndex: self.currentPageIndex)
          }
        }
      }
    }

    private func cacheChapterURLs() async throws {
      chapterURLCache = [:]
      for (index, link) in readingOrder.enumerated() {
        let normalizedHref = Self.normalizedHref(link.href ?? "")
        guard
          let href = link.href,
          let cachedURL = await OfflineManager.shared.cachedOfflineWebPubResourceURL(
            instanceId: AppConfig.current.instanceId,
            bookId: bookId,
            href: href
          )
        else {
          let rootPath = resourceRootURL?.path ?? "unknown"
          logger.error(
            "❌ Offline WebPub resource missing for book \(bookId): chapterIndex=\(index), href=\(normalizedHref), originalHref=\(link.href ?? "<missing>"), root=\(rootPath)"
          )
          throw AppErrorType.unknown(message: offlineEpubRecoveryMessage())
        }
        chapterURLCache[index] = cachedURL
      }
    }

    private func offlineEpubRecoveryMessage() -> String {
      "Offline EPUB files are incomplete. Please delete and re-download this book."
    }

    private func loadTextLengthCache() {
      guard let rootURL = resourceRootURL else { return }
      let cacheURL = rootURL.appendingPathComponent("text-length.json", isDirectory: false)
      guard let data = try? Data(contentsOf: cacheURL) else { return }
      if let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
        textLengthCache = decoded
      }
    }

    private func saveTextLengthCache() {
      guard let rootURL = resourceRootURL else { return }
      let cacheURL = rootURL.appendingPathComponent("text-length.json", isDirectory: false)
      if let data = try? JSONEncoder().encode(textLengthCache) {
        try? data.write(to: cacheURL, options: [.atomic])
      }
    }

    private func pageCountCacheKey(for href: String, viewport: CGSize) -> String {
      let sizeKey = "\(Int(viewport.width))x\(Int(viewport.height))"
      let prefsKey = preferences.rawValue
      return "\(href)|\(sizeKey)|\(prefsKey)|\(theme.rawValue)"
    }

    private func chapterIndexForHref(_ href: String) -> Int? {
      let normalized = Self.normalizedHref(href)
      return readingOrder.firstIndex { Self.normalizedHref($0.href ?? "") == normalized }
    }

    /// Syncs the remote progression into local storage. Returns `true` when the
    /// fetch failed transiently, meaning the server-side position is unknown.
    private func syncRemoteProgressionToLocal(bookId: String) async -> Bool {
      guard let database = await DatabaseOperator.databaseIfConfigured() else { return true }

      let remoteState = await BookService.fetchRemoteWebPubProgression(bookId: bookId)

      switch remoteState {
      case .available(let progression):
        await database.updateBookEpubProgression(
          bookId: bookId,
          progression: progression
        )
        logger.debug(
          "Synced remote EPUB progression to local storage: href=\(progression.locator.href), progression=\(progression.locator.locations?.progression ?? 0)"
        )
        return false
      case .missing:
        // A bare GET must never destroy a locally saved position: a busy or
        // misbehaving server can answer with a missing-shaped response, and
        // wiping local state here makes the reader reopen at page 0 and then
        // upload that regressed position back to the server. Only record
        // "missing" when there is no local progression to lose.
        if await database.fetchBookEpubProgression(bookId: bookId) == nil {
          await database.updateBookEpubProgression(
            bookId: bookId,
            progression: nil
          )
          logger.debug("Synced remote EPUB progression to local storage: missing progression")
        } else {
          logger.warning(
            "⚠️ Remote EPUB progression reported missing but a local progression exists; keeping local position for book \(bookId)"
          )
        }
        return false
      case .retryableFailure(let error):
        logger.warning(
          "Failed to fetch remote EPUB progression for book \(bookId): \(error.localizedDescription)"
        )
        return true
      case .invalidPayload(let error):
        // Same rule as .missing: never downgrade a local available progression
        // on an unparseable or non-retryable response.
        if await database.fetchBookEpubProgression(bookId: bookId) == nil {
          await database.updateBookEpubProgression(
            bookId: bookId,
            progression: nil
          )
        }
        logger.warning(
          "Ignoring non-retryable remote EPUB progression payload for book \(bookId): \(error.localizedDescription)"
        )
        return false
      }
    }

    /// Maps a page-based server read progress to a locator using the WebPub
    /// positions endpoint. Returns nil when the page cannot be mapped, in which
    /// case the caller must treat the position as unknown rather than falling
    /// back to the first page.
    private func restoreProgressionFromServerPage(
      bookId: String,
      page: Int,
      database: DatabaseOperator
    ) async -> R2Progression? {
      guard
        let progression = await EpubPageProgressionMapper.progression(
          bookId: bookId,
          page: page
        )
      else {
        return nil
      }

      guard chapterIndexForHref(progression.locator.href) != nil else {
        logger.warning(
          "⚠️ [Progress/Epub] Position locator does not match any chapter: book=\(bookId), href=\(progression.locator.href)"
        )
        return nil
      }

      await database.updateBookEpubProgression(bookId: bookId, progression: progression)
      logger.info(
        "📖 [Progress/Epub] Resumed from page-based server progress: book=\(bookId), page=\(page), href=\(progression.locator.href)"
      )
      return progression
    }

    private func stripResourcePrefix(_ href: String) -> String {
      if let range = href.range(of: "/resource/", options: .backwards) {
        return String(href[range.upperBound...])
      }
      return href
    }

    private func maxProgressionOverride(for href: String) async -> Float? {
      let normalizedHref = Self.normalizedHref(href)
      if let cached = maxProgressionByHref[normalizedHref] {
        return cached
      }
      guard !AppConfig.isOffline, !bookId.isEmpty else { return nil }

      if let task = positionsLoadTask {
        let map = await task.value
        return map[normalizedHref]
      }

      let task = Task { [bookId] in
        do {
          let positions = try await BookService.getWebPubPositions(bookId: bookId)
          var map: [String: Float] = [:]
          for locator in positions.positions {
            guard let progression = locator.locations?.progression else { continue }
            let key = Self.normalizedHref(locator.href)
            let existing = map[key] ?? -1
            if progression > existing {
              map[key] = progression
            }
          }
          return map
        } catch {
          return [:]
        }
      }

      positionsLoadTask = task
      let map = await task.value
      positionsLoadTask = nil
      if !map.isEmpty {
        maxProgressionByHref = map
      }
      return map[normalizedHref]
    }

    nonisolated private static func normalizedHref(_ href: String) -> String {
      var trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)

      // Handle full Komga resource URLs
      if let range = trimmed.range(of: "/resource/", options: .backwards) {
        trimmed = String(trimmed[range.upperBound...])
      }

      if let components = URLComponents(string: trimmed), !components.path.isEmpty {
        return components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      }
      return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static var defaultViewportSize: CGSize {
      #if os(iOS)
        return UIScreen.main.bounds.size
      #elseif os(macOS)
        if let screen = NSScreen.main {
          return screen.frame.size
        }
        return CGSize(width: 1280, height: 800)
      #else
        return CGSize(width: 1280, height: 800)
      #endif
    }
  }

#endif
