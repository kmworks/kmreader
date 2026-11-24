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

  @MainActor
  @Observable
  class EpubReaderViewModel {
    var isLoading = true
    var errorMessage: String?
    var loadingStage: LoadingStage = .fetchingMetadata
    var downloadProgress: Double = 0.0
    var downloadBytesReceived: Int64 = 0
    var downloadBytesExpected: Int64?

    var tableOfContents: [WebPubLink] = []
    var currentChapterIndex: Int = 0
    var currentPageIndex: Int = 0
    private(set) var navigationID = UUID()
    private(set) var targetChapterIndex: Int?
    private(set) var targetPageIndex: Int?
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
    // Chapters that failed to render show a placeholder error page; they must
    // not emit reading progress until a layout succeeds again.
    private var failedChapterIndexes: Set<Int> = []
    private var chapterURLCache: [Int: URL] = [:]
    private var textLengthCache: [String: Int] = [:]
    private var chapterTextWeights: [Int: Int] = [:]
    private var totalTextWeight: Int = 0
    private var hasFullTextWeights = false
    private var tocTitleByHref: [String: String] = [:]
    private var maxProgressionByHref: [String: Float] = [:]
    private var positionsLoadTask: Task<[String: Float], Never>?
    private var textLengthTask: Task<Void, Never>?
    /// When the remote progression fetch fails transiently and there is no local
    /// progression to restore from, the reader falls back to page 0. Submitting
    /// that fallback position would regress the server's progress, so all
    /// progression submissions are suppressed for the session.
    private var progressSubmissionSuppressed = false
    /// Re-attempts the remote progression fetch with exponential backoff after
    /// a transient failure, so the session-long suppression lifts as soon as
    /// the server becomes reachable again.
    private var progressionRetryTask: Task<Void, Never>?
    private var progressionNavigation: EpubProgressionNavigation?
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

      navigationID = UUID()
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
      progressionNavigation = nil
      progressSubmissionSuppressed = false
      progressionRetryTask?.cancel()
      progressionRetryTask = nil
      linkBackStack = []
      pendingAnchor = nil
      endPagePreviousBook = nil
      endPageNextBook = nil
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
          var remoteProgressUnavailable = false
          if AppConfig.isOffline {
            savedProgression = await database.fetchBookEpubProgression(bookId: bookId, instanceId: instanceId)
          } else {
            let result = await syncRemoteProgressionToLocal(bookId: bookId, instanceId: instanceId)
            switch result {
            case .available(let progression):
              savedProgression = progression
            case .missing:
              break
            case .retryableFailure(let localProgression):
              savedProgression = localProgression
              remoteFetchFailed = true
            case .unavailable:
              remoteProgressUnavailable = true
            }
          }
          guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else { return }

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
              "⚠️ [Progress/Epub] Remote progression fetch failed and no local progression exists; suppressing progress submission until a retry succeeds: book=\(bookId)"
            )
            scheduleProgressionFetchRetry(bookId: bookId, instanceId: instanceId)
          } else if remoteProgressUnavailable && savedProgression == nil {
            progressSubmissionSuppressed = true
          }
        }

        if let savedProgression {
          logger.debug(
            "Fetched saved progression: href=\(savedProgression.locator.href), progression=\(savedProgression.locator.locations?.progression ?? 0)"
          )
          if let chapterIndex = chapterIndexForHref(savedProgression.locator.href) {
            logger.debug("Matched progression to chapterIndex=\(chapterIndex)")
            progressionNavigation = EpubProgressionNavigation(
              chapterIndex: chapterIndex,
              progression: min(max(Double(savedProgression.locator.locations?.progression ?? 0), 0), 1),
              restoresRemoteProgress: false
            )
          } else {
            logger.debug("Failed to match progression href to any chapter in readingOrder")
          }
        }

        refreshChapterPageCounts(keepingCurrent: false)
        refreshChapterTextWeights()

        if let navigation = progressionNavigation {
          let chapterIndex = navigation.chapterIndex
          let pageCount = chapterPageCounts[chapterIndex] ?? 1
          let pageIndex = navigation.pageIndex(pageCount: pageCount)
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
        navigateToPage(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex + 1)
      } else if currentChapterIndex + 1 < chapterCount {
        navigateToPage(chapterIndex: currentChapterIndex + 1, pageIndex: 0)
      }
    }

    func goToPreviousPage() {
      guard !readingOrder.isEmpty else { return }
      if currentPageIndex > 0 {
        navigateToPage(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex - 1)
      } else if currentChapterIndex > 0 {
        let previousChapterIndex = currentChapterIndex - 1
        navigateToPage(chapterIndex: previousChapterIndex, pageIndex: -1)
      }
    }

    func goToChapter(link: WebPubLink) {
      guard let href = link.href, let chapterIndex = chapterIndexForHref(href) else { return }
      navigateToPage(chapterIndex: chapterIndex, pageIndex: 0)
    }

    // MARK: - End Page Adjacent Books

    /// Previous/next sibling in the book's series (or read list), for the
    /// end-page continuation cards.
    private(set) var endPagePreviousBook: Book?
    private(set) var endPageNextBook: Book?

    func loadEndPageAdjacentBooks(bookId: String, readListId: String?) async {
      let instanceId = AppConfig.current.instanceId
      let books = await ReaderContentService().resolveAdjacentBooks(for: bookId, readListId: readListId)
      guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else { return }
      endPagePreviousBook = books.previous
      endPageNextBook = books.next
    }

    func navigateToURL(_ url: URL) {
      guard let chapterIndex = chapterIndex(for: url) else { return }
      navigateToChapterLink(chapterIndex: chapterIndex, fragment: url.fragment)
    }

    func navigateToChapter(containing url: URL) {
      guard let chapterIndex = chapterIndex(for: url) else { return }
      navigateToChapterLink(chapterIndex: chapterIndex, fragment: nil)
    }

    private func chapterIndex(for url: URL) -> Int? {
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
          return chapterIndex
        }
      }
      return nil
    }

    private func navigateToChapterLink(chapterIndex: Int, fragment: String?) {
      if chapterIndex == currentChapterIndex, fragment == nil || fragment?.isEmpty == true {
        navigateToPage(chapterIndex: chapterIndex, pageIndex: 0)
        return
      }
      pushLinkBack(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)
      navigateToPage(chapterIndex: chapterIndex, pageIndex: 0)
      if let fragment, !fragment.isEmpty {
        pendingAnchor = EpubAnchorNavigation(chapterIndex: chapterIndex, anchor: fragment)
      }
    }

    // MARK: - In-book link back stack

    /// Origin positions of in-book link jumps (footnotes, cross-references),
    /// so the reader can return to where the link was tapped.
    private(set) var linkBackStack: [(chapterIndex: Int, pageIndex: Int)] = []
    private var pendingAnchor: EpubAnchorNavigation?

    var canReturnFromLink: Bool { !linkBackStack.isEmpty }

    func pushLinkBack(chapterIndex: Int, pageIndex: Int) {
      if let last = linkBackStack.last,
        last.chapterIndex == chapterIndex, last.pageIndex == pageIndex
      {
        return
      }
      linkBackStack.append((chapterIndex: chapterIndex, pageIndex: pageIndex))
    }

    func navigationRequiresFullExtent(for chapterIndex: Int) -> Bool {
      progressionNavigation?.chapterIndex == chapterIndex || pendingAnchor?.chapterIndex == chapterIndex
    }

    func pendingAnchorNavigation(for chapterIndex: Int) -> EpubAnchorNavigation? {
      guard pendingAnchor?.chapterIndex == chapterIndex else { return nil }
      return pendingAnchor
    }

    func acknowledgeAnchorNavigation(_ navigation: EpubAnchorNavigation) -> Bool {
      guard pendingAnchor == navigation else { return false }
      pendingAnchor = nil
      return true
    }

    func returnFromLink() {
      guard let entry = linkBackStack.popLast() else { return }
      navigateToPage(chapterIndex: entry.chapterIndex, pageIndex: entry.pageIndex)
    }

    func pageDidChange() {
      guard pendingAnchor == nil, progressionNavigation == nil else { return }
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
      guard !failedChapterIndexes.contains(chapterIndex) else {
        logger.debug(
          "⏭️ [Progress/Epub] Skip capture: chapter failed to render, book=\(bookId), chapterIndex=\(chapterIndex)"
        )
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
      guard progressionNavigation == nil, pendingAnchor == nil else { return }
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
      guard !failedChapterIndexes.contains(chapterIndex) else {
        logger.debug(
          "⏭️ [Progress/Epub] Skip flush: chapter failed to render, book=\(bookId), chapterIndex=\(chapterIndex)"
        )
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

    func requestedProgression(for chapterIndex: Int) -> Double? {
      guard let navigation = progressionNavigation, navigation.chapterIndex == chapterIndex else { return nil }
      return navigation.progression
    }

    func updateChapterPageCount(_ pageCount: Int, for chapterIndex: Int) {
      guard chapterIndex >= 0, chapterIndex < readingOrder.count else { return }
      // A produced page count means the chapter laid out successfully.
      failedChapterIndexes.remove(chapterIndex)
      let normalizedCount = max(1, pageCount)

      chapterPageCounts[chapterIndex] = normalizedCount

      normalizeCurrentPosition(adjustPageCount: false)
      normalizeTargetPosition(adjustPageCount: false)
      updateLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)

      // Store in memory cache only (no file persistence)
      let effectiveViewport = viewportSize.width > 0 ? viewportSize : Self.defaultViewportSize
      guard let href = readingOrder[chapterIndex].href else { return }
      let cacheKey = pageCountCacheKey(for: href, viewport: effectiveViewport)
      pageCountCache[cacheKey] = normalizedCount
      if progressionNavigation?.chapterIndex == chapterIndex, let page = resolvedProgressionPage() {
        targetChapterIndex = chapterIndex
        targetPageIndex = page
      }
    }

    func markChapterLoadFailed(_ chapterIndex: Int) {
      chapterPageCounts[chapterIndex] = 1
      failedChapterIndexes.insert(chapterIndex)
      normalizeCurrentPosition(adjustPageCount: false)
      normalizeTargetPosition(adjustPageCount: false)
      updateLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)
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

    // MARK: - Navigation

    func clearNavigationTarget() {
      targetChapterIndex = nil
      targetPageIndex = nil
    }

    func commitInteractiveNavigation(chapterIndex: Int, pageIndex: Int) {
      if progressionNavigation != nil || pendingAnchor != nil || targetChapterIndex != nil {
        navigationID = UUID()
      }
      progressionNavigation = nil
      pendingAnchor = nil
      clearNavigationTarget()
      currentChapterIndex = chapterIndex
      currentPageIndex = pageIndex
      pageDidChange()
    }

    func commitPosition(_ landing: EpubPageLanding) {
      guard landing.navigationID == navigationID,
        readingOrder.indices.contains(landing.chapterIndex), landing.pageCount > 0
      else { return }
      if !failedChapterIndexes.contains(landing.chapterIndex) {
        updateChapterPageCount(landing.pageCount, for: landing.chapterIndex)
      }
      currentChapterIndex = landing.chapterIndex
      currentPageIndex = max(0, min(landing.pageIndex, landing.pageCount - 1))
      clearNavigationTarget()
      guard finishProgressionNavigationIfLanded(pageCount: landing.pageCount) else { return }
      pageDidChange()
    }

    func navigateToPage(chapterIndex: Int, pageIndex: Int) {
      guard !readingOrder.isEmpty else { return }
      navigationID = UUID()
      progressionNavigation = nil
      pendingAnchor = nil
      let normalizedChapterIndex = max(0, min(chapterIndex, readingOrder.count - 1))
      let normalizedPageIndex =
        pageIndex < 0
        ? -1
        : normalizedPageIndex(pageIndex, chapterIndex: normalizedChapterIndex, adjustPageCount: true)
      targetChapterIndex = normalizedChapterIndex
      targetPageIndex = normalizedPageIndex
    }

    private func navigateToProgression(
      chapterIndex: Int, progression: Double, restoresRemoteProgress: Bool = false
    ) {
      guard readingOrder.indices.contains(chapterIndex) else { return }
      navigationID = UUID()
      pendingAnchor = nil
      progressionNavigation = EpubProgressionNavigation(
        chapterIndex: chapterIndex,
        progression: min(max(progression, 0), 1),
        restoresRemoteProgress: restoresRemoteProgress
      )
      targetChapterIndex = chapterIndex
      targetPageIndex = resolvedProgressionPage() ?? 0
    }

    private func resolvedProgressionPage() -> Int? {
      guard let navigation = progressionNavigation,
        !failedChapterIndexes.contains(navigation.chapterIndex),
        let href = readingOrder[navigation.chapterIndex].href
      else { return nil }
      let viewport = viewportSize.width > 0 ? viewportSize : Self.defaultViewportSize
      let key = pageCountCacheKey(for: href, viewport: viewport)
      guard let count = pageCountCache[key] else { return nil }
      return navigation.pageIndex(pageCount: count)
    }

    private func finishProgressionNavigationIfLanded(pageCount: Int) -> Bool {
      guard let navigation = progressionNavigation else { return true }
      guard currentChapterIndex == navigation.chapterIndex,
        !failedChapterIndexes.contains(navigation.chapterIndex),
        currentPageIndex == navigation.pageIndex(pageCount: pageCount)
      else {
        if let page = resolvedProgressionPage() {
          targetChapterIndex = navigation.chapterIndex
          targetPageIndex = page
        }
        return false
      }
      progressionNavigation = nil
      if navigation.restoresRemoteProgress {
        progressSubmissionSuppressed = false
        sessionStartPosition = (currentChapterIndex, currentPageIndex)
      }
      return true
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

    var totalSeekFraction: Double? {
      guard let location = pageLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex) else {
        return nil
      }
      if hasFullTextWeights {
        return totalProgression(
          location: location,
          chapterProgress: Double(location.pageIndex) / Double(max(1, location.pageCount))
        )
      }
      let totalPages = totalPageCount()
      guard totalPages > 0 else { return nil }
      return Double(pageOffsetBeforeChapter(location.chapterIndex) + location.pageIndex) / Double(totalPages)
    }

    /// Seeks to the page-start fraction exposed by totalSeekFraction.
    func seek(toTotalFraction fraction: Double) {
      let target = min(max(fraction, 0), 1)
      guard target != totalSeekFraction else { return }
      if hasFullTextWeights, totalTextWeight > 0 {
        let targetWeight = target * Double(totalTextWeight)
        var accumulated = 0.0
        for idx in 0..<readingOrder.count {
          let weight = Double(chapterTextWeights[idx] ?? 0)
          if accumulated + weight > targetWeight || idx == readingOrder.count - 1 {
            let within = weight > 0 ? min(max((targetWeight - accumulated) / weight, 0), 1) : 0
            navigateToProgression(chapterIndex: idx, progression: within)
            return
          }
          accumulated += weight
        }
        return
      }

      let totalPages = totalPageCount()
      guard totalPages > 0 else { return }
      let overallIndex = min(totalPages - 1, max(0, Int((target * Double(totalPages)).rounded(.down))))
      for idx in 0..<readingOrder.count {
        let count = max(1, chapterPageCounts[idx] ?? 1)
        let offset = pageOffsetBeforeChapter(idx)
        if overallIndex < offset + count || idx == readingOrder.count - 1 {
          navigateToPage(chapterIndex: idx, pageIndex: min(count - 1, overallIndex - offset))
          return
        }
      }
    }

    private func updateProgression(
      chapterIndex: Int,
      pageIndex: Int,
      chapterProgressOverride: Double? = nil,
      totalProgressOverride: Double? = nil
    ) async {
      guard !progressSubmissionSuppressed, progressionNavigation == nil, pendingAnchor == nil else {
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

    private func syncRemoteProgressionToLocal(bookId: String, instanceId: String) async -> EpubProgressionSyncResult {
      guard let database = await DatabaseOperator.databaseIfConfigured() else { return .unavailable }
      guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else {
        return .unavailable
      }
      await ProgressSyncService.shared.syncPendingProgress(instanceId: instanceId)
      guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else {
        return .unavailable
      }
      let remoteState = await BookService.fetchRemoteWebPubProgression(bookId: bookId)
      guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else {
        return .unavailable
      }

      switch remoteState {
      case .available(let progression):
        await database.updateBookEpubProgression(bookId: bookId, instanceId: instanceId, progression: progression)
        return .available(progression)
      case .missing:
        // A remote missing response must never erase a saved local position.
        let localProgression = await database.fetchBookEpubProgression(bookId: bookId, instanceId: instanceId)
        guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else {
          return .unavailable
        }
        if let localProgression { return .available(localProgression) }
        await database.updateBookEpubProgression(bookId: bookId, instanceId: instanceId, progression: nil)
        return .missing
      case .retryableFailure(let error):
        logger.warning("Failed to fetch remote EPUB progression for book \(bookId): \(error.localizedDescription)")
        let localProgression = await database.fetchBookEpubProgression(bookId: bookId, instanceId: instanceId)
        return .retryableFailure(localProgression: localProgression)
      case .invalidPayload(let error):
        logger.warning("Ignoring invalid remote EPUB progression for book \(bookId): \(error.localizedDescription)")
        if let localProgression = await database.fetchBookEpubProgression(bookId: bookId, instanceId: instanceId) {
          return .available(localProgression)
        }
        return .unavailable
      }
    }

    private func scheduleProgressionFetchRetry(bookId: String, instanceId: String) {
      progressionRetryTask?.cancel()
      let restorationNavigationID = navigationID
      progressionRetryTask = Task { [weak self] in
        var delay: TimeInterval = 2
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(delay))
          guard !Task.isCancelled, let self, self.bookId == bookId,
            AppConfig.current.instanceId == instanceId, self.progressSubmissionSuppressed
          else { return }
          let result = await self.syncRemoteProgressionToLocal(bookId: bookId, instanceId: instanceId)
          guard !Task.isCancelled, self.bookId == bookId, AppConfig.current.instanceId == instanceId else { return }
          if case .retryableFailure = result {
            delay = min(delay * 2, 60)
            continue
          }
          self.applyRetriedRemoteProgression(result, navigationID: restorationNavigationID)
          return
        }
      }
    }

    private func applyRetriedRemoteProgression(_ result: EpubProgressionSyncResult, navigationID: UUID) {
      switch result {
      case .missing:
        progressSubmissionSuppressed = false
      case .available(let progression):
        guard let chapterIndex = chapterIndexForHref(progression.locator.href) else {
          logger.warning("Remote EPUB progression retry has an unknown chapter; keeping submission suppressed")
          return
        }
        guard self.navigationID == navigationID, currentChapterIndex == 0, currentPageIndex == 0 else {
          logger.warning("Remote EPUB progression retry completed after navigation; keeping submission suppressed")
          return
        }
        navigateToProgression(
          chapterIndex: chapterIndex,
          progression: Double(progression.locator.locations?.progression ?? 0),
          restoresRemoteProgress: true
        )
      case .retryableFailure, .unavailable:
        break
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
