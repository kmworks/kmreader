import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import os

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@MainActor
final class ReaderPageLoadScheduler {
  typealias PresentationInvalidationHandler = @MainActor (ReaderPagePresentationInvalidation) -> Void

  private struct TrackedTaskRecord<Success: Sendable> {
    let token: UUID
    let task: Task<Success, Never>
  }

  private let logger = AppLogger(.reader)
  private let pageImageCache = ImageCache()
  private var preloadWindow: ReaderPreloadWindow

  private var readerPages: [ReaderPage] = []
  private var readerPageIndexByID: [ReaderPageID: Int] = [:]
  private var currentPageID: ReaderPageID?
  private var presentationInvalidationHandler: PresentationInvalidationHandler?

  private var preloadedImagesByID: [ReaderPageID: PlatformImage] = [:]
  private var animatedPageStates: [ReaderPageID: Bool] = [:]
  private var animatedPageSourceFileURLs: [ReaderPageID: URL] = [:]
  private var failedImageLoadsByID: [ReaderPageID: ReaderPageLoadFailure] = [:]

  private var downloadingTasks: [ReaderPageID: TrackedTaskRecord<(url: URL?, failure: ReaderPageLoadFailure?)>] = [:]
  private var upscalingTasks: [ReaderPageID: TrackedTaskRecord<URL?>] = [:]
  private var preloadingImageTasks: [ReaderPageID: TrackedTaskRecord<PlatformImage?>] = [:]
  private var lastPreloadRequestTime: Date?
  private var preloadTask: Task<Void, Never>?
  private var visiblePageIDs: [ReaderPageID] = []

  init(preloadWindow: ReaderPreloadWindow = ReaderPreloadWindow.balanced) {
    self.preloadWindow = preloadWindow

    #if os(iOS) || os(tvOS)
      MemoryWarningCenter.shared.addListener(self)
    #endif
  }

  func setPresentationInvalidationHandler(_ handler: PresentationInvalidationHandler?) {
    presentationInvalidationHandler = handler
  }

  func updatePreloadWindow(_ preloadWindow: ReaderPreloadWindow) {
    guard self.preloadWindow != preloadWindow else { return }
    self.preloadWindow = preloadWindow
    preloadTask?.cancel()
    preloadTask = nil
    lastPreloadRequestTime = nil

    let keepPageIDs = prioritizedPageIDs(around: visiblePageIDs)
    if !keepPageIDs.isEmpty {
      cancelTrackedTasksOutsideWindow(&downloadingTasks, keeping: keepPageIDs)
      cancelTrackedTasksOutsideWindow(&upscalingTasks, keeping: keepPageIDs)
      cancelTrackedTasksOutsideWindow(&preloadingImageTasks, keeping: keepPageIDs)
    }

    cleanupDistantImagesAroundCurrentPage()
  }

  func updateReaderPages(_ readerPages: [ReaderPage]) {
    self.readerPages = readerPages
    var indexMap: [ReaderPageID: Int] = [:]
    indexMap.reserveCapacity(readerPages.count)
    for (index, readerPage) in readerPages.enumerated() {
      indexMap[readerPage.id] = index
    }
    readerPageIndexByID = indexMap

    if let currentPageID, readerPageIndexByID[currentPageID] == nil {
      self.currentPageID = readerPages.first?.id
    }
  }

  func updateCurrentPageID(_ pageID: ReaderPageID?) {
    if let pageID, readerPageIndexByID[pageID] != nil {
      currentPageID = pageID
    } else {
      currentPageID = readerPages.first?.id
    }
  }

  func getPageImageFileURL(pageID: ReaderPageID) async -> URL? {
    guard let pageIndex = pageIndex(for: pageID) else { return nil }
    return await getPageImageFileURL(pageIndex: pageIndex).url
  }

  func preloadedImage(for pageID: ReaderPageID) -> PlatformImage? {
    preloadedImagesByID[pageID]
  }

  func hasPendingImageLoad(for pageID: ReaderPageID) -> Bool {
    preloadingImageTasks[pageID] != nil
      || downloadingTasks[pageID] != nil
      || upscalingTasks[pageID] != nil
  }

  func hasFailedImageLoad(for pageID: ReaderPageID) -> Bool {
    failedImageLoadsByID[pageID] != nil
  }

  func imageLoadFailure(for pageID: ReaderPageID) -> ReaderPageLoadFailure? {
    failedImageLoadsByID[pageID]
  }

  func retryImageLoad(for pageID: ReaderPageID) {
    failedImageLoadsByID.removeValue(forKey: pageID)
    invalidatePresentation(.pages([pageID]))
    Task { [weak self] in
      _ = await self?.preloadImage(for: pageID)
    }
  }

  func prioritizeVisiblePageLoads(for pageIDs: [ReaderPageID]) {
    visiblePageIDs = pageIDs

    let keepPageIDs = prioritizedPageIDs(around: pageIDs)
    guard !keepPageIDs.isEmpty else { return }

    preloadTask?.cancel()
    preloadTask = nil
    lastPreloadRequestTime = nil

    cancelTrackedTasksOutsideWindow(&downloadingTasks, keeping: keepPageIDs)
    cancelTrackedTasksOutsideWindow(&upscalingTasks, keeping: keepPageIDs)
    cancelTrackedTasksOutsideWindow(&preloadingImageTasks, keeping: keepPageIDs)
  }

  func preloadPages(bypassThrottle: Bool = false) async {
    let now = Date()
    if !bypassThrottle,
      let last = lastPreloadRequestTime,
      now.timeIntervalSince(last) < 0.3
    {
      return
    }
    lastPreloadRequestTime = now

    let pagesToPreload = pageWindowEntries(
      around: currentPageID,
      before: preloadWindow.preloadBefore,
      after: preloadWindow.preloadAfter
    )
    guard !pagesToPreload.isEmpty else { return }

    preloadTask?.cancel()
    let pageIDsToPreload = pagesToPreload.map(\.pageID)
    preloadTask = Task { [weak self] in
      guard let self else { return }

      for pageID in pageIDsToPreload {
        guard !Task.isCancelled else { return }
        if self.preloadedImage(for: pageID) != nil { continue }
        _ = await self.preloadImage(for: pageID)
      }

      if !Task.isCancelled {
        self.cleanupDistantImagesAroundCurrentPage()
      }
    }
  }

  func cleanupDistantImagesAroundCurrentPage() {
    var keepPageIDs = Set(
      pageWindowEntries(
        around: currentPageID,
        before: preloadWindow.keepRangeBefore,
        after: preloadWindow.keepRangeAfter
      ).map(\.pageID)
    )
    keepPageIDs.formUnion(visiblePageIDs)
    guard !keepPageIDs.isEmpty else { return }

    let imageKeysToRemove = preloadedImagesByID.keys.filter { !keepPageIDs.contains($0) }
    for key in imageKeysToRemove {
      clearPreloadedImage(for: key)
    }

    let animatedKeysToRemove = Set(animatedPageStates.keys)
      .union(animatedPageSourceFileURLs.keys)
      .filter { !keepPageIDs.contains($0) }

    for key in animatedKeysToRemove {
      updateAnimatedPresentation(knownAnimatedState: nil, sourceFileURL: nil, for: key)
    }
  }

  /// Drop decoded bitmaps for every page outside the visible set, keeping
  /// only what's strictly required to render the current screen. More
  /// aggressive than `cleanupDistantImagesAroundCurrentPage` (which keeps
  /// the full `keepRangeBefore`/`keepRangeAfter` keep-window of ~10 pages)
  /// because this is invoked under memory pressure, when iOS would
  /// otherwise reclaim the view tree and force a full reader rebuild.
  ///
  /// The on-disk image cache survives this prune untouched; the next
  /// preload cycle (driven by the next page change) re-decodes the keep
  /// window from disk transparently. Falls back to keeping `currentPageID`
  /// when `visiblePageIDs` is unexpectedly empty so the user never loses
  /// the page they're actively reading.
  func pruneToVisiblePagesOnly() {
    var keepPageIDs = Set(visiblePageIDs)
    if keepPageIDs.isEmpty, let currentPageID {
      keepPageIDs.insert(currentPageID)
    }

    let imageKeysToRemove = preloadedImagesByID.keys.filter { !keepPageIDs.contains($0) }
    for key in imageKeysToRemove {
      clearPreloadedImage(for: key)
    }

    let animatedKeysToRemove = Set(animatedPageStates.keys)
      .union(animatedPageSourceFileURLs.keys)
      .filter { !keepPageIDs.contains($0) }

    for key in animatedKeysToRemove {
      updateAnimatedPresentation(knownAnimatedState: nil, sourceFileURL: nil, for: key)
    }

    logger.debug(
      "🧹 [Reader/Memory] Pruned to visible pages: kept=\(keepPageIDs.count), removed=\(imageKeysToRemove.count)"
    )
  }

  func isAnimatedPage(for pageID: ReaderPageID) -> Bool {
    animatedPageStates[pageID] == true
  }

  func shouldPrepareAnimatedPlayback(for pageID: ReaderPageID) -> Bool {
    animatedPageStates[pageID] != false
  }

  func animatedSourceFileURL(for pageID: ReaderPageID) -> URL? {
    guard animatedPageStates[pageID] == true else { return nil }
    guard let fileURL = animatedPageSourceFileURLs[pageID] else { return nil }
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return fileURL
  }

  func prepareAnimatedPagePlaybackURL(pageID: ReaderPageID) async {
    guard let pageIndex = pageIndex(for: pageID) else { return }
    await prepareAnimatedPagePlaybackURL(pageIndex: pageIndex)
  }

  func preloadImage(for pageID: ReaderPageID) async -> PlatformImage? {
    if let cached = preloadedImagesByID[pageID] {
      return cached
    }

    guard let pageIndex = pageIndex(for: pageID) else {
      return nil
    }

    if let existingTask = preloadingImageTasks[pageID] {
      return await existingTask.task.value
    }

    let taskToken = UUID()
    let preloadTask = Task<PlatformImage?, Never> { [weak self] in
      guard let self else { return nil }
      let (image, animatedSourceFileURL, failure) = await self.preloadDecodedPageImage(pageIndex: pageIndex)
      guard !Task.isCancelled else { return nil }

      self.updateAnimatedPresentation(
        knownAnimatedState: animatedSourceFileURL != nil,
        sourceFileURL: animatedSourceFileURL,
        for: pageID
      )
      guard let image else {
        self.markImageLoadFailed(for: pageID, failure: failure ?? .unknown)
        return nil
      }

      self.setPreloadedImage(image, for: pageID)
      return image
    }

    preloadingImageTasks[pageID] = TrackedTaskRecord(token: taskToken, task: preloadTask)
    let image = await preloadTask.value
    removeTrackedTaskIfCurrent(for: pageID, token: taskToken, from: &preloadingImageTasks)
    return image
  }

  func clearPreloadedImages() {
    preloadTask?.cancel()
    preloadTask = nil
    lastPreloadRequestTime = nil

    for (_, taskRecord) in downloadingTasks {
      taskRecord.task.cancel()
    }
    downloadingTasks.removeAll()

    for (_, taskRecord) in upscalingTasks {
      taskRecord.task.cancel()
    }
    upscalingTasks.removeAll()

    for (_, taskRecord) in preloadingImageTasks {
      taskRecord.task.cancel()
    }
    preloadingImageTasks.removeAll()

    preloadedImagesByID.removeAll()
    animatedPageStates.removeAll()
    animatedPageSourceFileURLs.removeAll()
    failedImageLoadsByID.removeAll()
    invalidatePresentation(.all)
    logger.debug("🗑️ Cleared all preloaded images and cancelled tasks")
  }

  func discardPreloadedImages(forBookId bookId: String) {
    let pageIDs = Set(readerPages.lazy.filter { $0.bookId == bookId }.map(\.id))
    guard !pageIDs.isEmpty else { return }

    cancelTrackedTasks(&upscalingTasks, matching: pageIDs)
    cancelTrackedTasks(&preloadingImageTasks, matching: pageIDs)

    var removedImageCount = 0
    for pageID in pageIDs {
      if preloadedImagesByID.removeValue(forKey: pageID) != nil {
        removedImageCount += 1
      }
      animatedPageStates.removeValue(forKey: pageID)
      animatedPageSourceFileURLs.removeValue(forKey: pageID)
      failedImageLoadsByID.removeValue(forKey: pageID)
    }

    logger.debug(
      "🗑️ Discarded preloaded images for book \(bookId): pages=\(pageIDs.count), removed=\(removedImageCount)"
    )
  }

  func resetForBookLoad() {
    clearPreloadedImages()
    readerPages.removeAll()
    readerPageIndexByID.removeAll()
    currentPageID = nil
    visiblePageIDs.removeAll()
  }

  private func pageIndex(for pageID: ReaderPageID) -> Int? {
    readerPageIndexByID[pageID]
  }

  private func readerPage(at pageIndex: Int) -> ReaderPage? {
    guard pageIndex >= 0 && pageIndex < readerPages.count else { return nil }
    return readerPages[pageIndex]
  }

  private func readerPageID(forPageIndex pageIndex: Int) -> ReaderPageID? {
    guard pageIndex >= 0 && pageIndex < readerPages.count else { return nil }
    return readerPages[pageIndex].id
  }

  private func pageWindowEntries(around pageID: ReaderPageID?, before: Int, after: Int)
    -> [(index: Int, pageID: ReaderPageID)]
  {
    guard let pageID, let centerIndex = pageIndex(for: pageID), !readerPages.isEmpty else { return [] }
    let lowerIndex = max(centerIndex - max(before, 0), 0)
    let upperIndex = min(centerIndex + max(after, 0), max(readerPages.count - 1, 0))
    guard lowerIndex <= upperIndex else { return [] }

    return readerPages[lowerIndex...upperIndex].enumerated().map { offset, readerPage in
      (index: lowerIndex + offset, pageID: readerPage.id)
    }
  }

  private func prioritizedPageIDs(around pageIDs: [ReaderPageID]) -> Set<ReaderPageID> {
    var keepPageIDs = Set(pageIDs)
    for pageID in pageIDs {
      keepPageIDs.formUnion(
        pageWindowEntries(
          around: pageID,
          before: preloadWindow.preloadBefore,
          after: preloadWindow.preloadAfter
        ).map(\.pageID)
      )
    }
    return keepPageIDs
  }

  private func setPreloadedImage(_ image: PlatformImage, for pageID: ReaderPageID) {
    failedImageLoadsByID.removeValue(forKey: pageID)
    preloadedImagesByID[pageID] = image
    invalidatePresentation(.pages([pageID]))
  }

  private func markImageLoadFailed(for pageID: ReaderPageID, failure: ReaderPageLoadFailure) {
    failedImageLoadsByID[pageID] = failure
    invalidatePresentation(.pages([pageID]))
  }

  private func clearPreloadedImage(for pageID: ReaderPageID) {
    guard preloadedImagesByID.removeValue(forKey: pageID) != nil else { return }
    invalidatePresentation(.pages([pageID]))
  }

  private func invalidatePresentation(_ invalidation: ReaderPagePresentationInvalidation) {
    presentationInvalidationHandler?(invalidation)
  }

  private func removeTrackedTaskIfCurrent<Success: Sendable>(
    for pageID: ReaderPageID,
    token: UUID,
    from tasks: inout [ReaderPageID: TrackedTaskRecord<Success>]
  ) {
    guard tasks[pageID]?.token == token else { return }
    tasks.removeValue(forKey: pageID)
  }

  private func cancelTrackedTasksOutsideWindow<Success: Sendable>(
    _ tasks: inout [ReaderPageID: TrackedTaskRecord<Success>],
    keeping keepPageIDs: Set<ReaderPageID>
  ) {
    let stalePageIDs = tasks.keys.filter { !keepPageIDs.contains($0) }
    for pageID in stalePageIDs {
      tasks[pageID]?.task.cancel()
      tasks.removeValue(forKey: pageID)
    }
  }

  private func cancelTrackedTasks<Success: Sendable>(
    _ tasks: inout [ReaderPageID: TrackedTaskRecord<Success>],
    matching pageIDs: Set<ReaderPageID>
  ) {
    let matchedPageIDs = tasks.keys.filter { pageIDs.contains($0) }
    for pageID in matchedPageIDs {
      tasks[pageID]?.task.cancel()
      tasks.removeValue(forKey: pageID)
    }
  }

  nonisolated private static func detectAnimatedState(for page: BookPage, fileURL: URL) -> Bool {
    guard page.isAnimatedImageCandidate else { return false }
    return AnimatedImageSupport.isAnimatedImageFile(at: fileURL)
  }

  private func getPageImageFileURL(pageIndex: Int) async -> (url: URL?, failure: ReaderPageLoadFailure?) {
    guard let readerPage = readerPage(at: pageIndex) else {
      logger.warning("⚠️ Invalid page index \(pageIndex), cannot load page image")
      return (nil, nil)
    }

    let pageID = readerPage.id
    let page = readerPage.page
    let currentBookId = readerPage.bookId

    if let existingTask = downloadingTasks[pageID] {
      logger.debug("⏳ Waiting for existing download task for page \(page.number) for book \(currentBookId)")
      let result = await existingTask.task.value
      if result.url != nil {
        return result
      }
      if let cachedFileURL = await getCachedImageFileURL(for: readerPage) {
        return (cachedFileURL, nil)
      }
      return (nil, result.failure)
    }

    let taskToken = UUID()
    let loadTask = Task<(url: URL?, failure: ReaderPageLoadFailure?), Never> {
      guard !Task.isCancelled else { return (nil, nil) }

      var failure: ReaderPageLoadFailure?

      do {
        if let offlineURL = try await OfflineManager.shared.getOfflinePageImageURL(
          instanceId: AppConfig.current.instanceId,
          bookId: currentBookId,
          page: page
        ) {
          self.logger.debug("✅ Using offline downloaded image for page \(page.number) for book \(currentBookId)")
          return (offlineURL, nil)
        }
      } catch {
        failure = .readDownloadFailed
      }

      if let cachedFileURL = await self.getCachedImageFileURL(for: readerPage) {
        self.logger.debug("✅ Using cached image for page \(page.number) for book \(currentBookId)")
        return (cachedFileURL, nil)
      }

      let instanceId = AppConfig.current.instanceId
      if let offlinePDFURL = await OfflineManager.shared.getOfflinePDFURL(
        instanceId: instanceId,
        bookId: currentBookId
      ) {
        if let renderedURL = await PdfOfflinePreparationService.shared.renderPageIfNeeded(
          instanceId: instanceId,
          bookId: currentBookId,
          documentURL: offlinePDFURL,
          pageNumber: page.number
        ) {
          self.logger.debug("✅ Rendered PDF page \(page.number) on demand for book \(currentBookId)")
          return (renderedURL, nil)
        }
      }

      if AppConfig.isOffline {
        self.logger.error("❌ Missing offline page \(page.number) for book \(currentBookId)")
        return (nil, failure ?? .offlineUnavailable)
      }

      self.logger.info("📥 Downloading page \(page.number) for book \(currentBookId)")

      do {
        guard let remoteURL = self.resolvedDownloadURL(for: page, bookId: currentBookId) else {
          self.logger.error("❌ Unable to resolve download URL for page \(page.number) in book \(currentBookId)")
          return (nil, failure)
        }

        let result = try await BookService.downloadImageResource(at: remoteURL)
        guard !Task.isCancelled else { return (nil, nil) }

        let data = result.data
        let dataSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)
        self.logger.info(
          "✅ Downloaded page \(page.number) successfully (\(dataSize)) for book \(currentBookId)"
        )

        await self.pageImageCache.storeImageData(
          data,
          bookId: currentBookId,
          page: page
        )

        if let fileURL = await self.getCachedImageFileURL(for: readerPage) {
          self.logger.debug("💾 Saved page \(page.number) to disk cache for book \(currentBookId)")
          return (fileURL, nil)
        }

        self.logger.error(
          "❌ Failed to get file URL after saving page \(page.number) to cache for book \(currentBookId)"
        )
        return (nil, failure)
      } catch {
        self.logger.error("❌ Failed to download page \(page.number) for book \(currentBookId): \(error)")
        return (nil, Self.loadFailure(for: error) ?? failure)
      }
    }

    downloadingTasks[pageID] = TrackedTaskRecord(token: taskToken, task: loadTask)
    let result = await loadTask.value
    removeTrackedTaskIfCurrent(for: pageID, token: taskToken, from: &downloadingTasks)
    return result
  }

  nonisolated private static func loadFailure(for error: Error) -> ReaderPageLoadFailure? {
    guard let apiError = error as? APIError else { return nil }
    switch apiError {
    case .serverError(let code, _, _, _, _), .httpError(let code, _, _, _, _):
      return .serverError(code)
    case .networkError(let underlying, _):
      if let appError = underlying as? AppErrorType {
        return .networkError(appError.description)
      }
      return .networkError(underlying.localizedDescription)
    default:
      return nil
    }
  }

  private func getCachedImageFileURL(for readerPage: ReaderPage) async -> URL? {
    if await pageImageCache.hasImage(bookId: readerPage.bookId, page: readerPage.page) {
      return pageImageCache.imageFileURL(bookId: readerPage.bookId, page: readerPage.page)
    }
    return nil
  }

  /// Decode budget in multiples of the current screen width; 2 keeps
  /// downsampled pages sharp through a 2× zoom.
  private static let pageDecodeZoomHeadroom: CGFloat = 2

  private var mainScreenPixelSize: CGSize? {
    #if os(iOS) || os(tvOS)
      return ReaderUpscaleDecision.screenPixelSize(for: UIScreen.main)
    #elseif os(macOS)
      guard let mainScreen = NSScreen.main else { return nil }
      return ReaderUpscaleDecision.screenPixelSize(for: mainScreen)
    #endif
  }

  /// Short-edge pixel budget for decoded pages. A short-edge cap serves both
  /// fit-screen (paged) and fit-width (webtoon) display and survives 90°
  /// rotation, which swaps the binding axis.
  private var pageShortEdgeCapPixels: CGFloat {
    (mainScreenPixelSize?.width ?? .infinity) * Self.pageDecodeZoomHeadroom
  }

  private func loadImageFromFile(fileURL: URL) async -> PlatformImage? {
    let shortEdgeCapPixels = pageShortEdgeCapPixels
    let downsampled = await Task.detached(priority: .userInitiated) {
      await ImageDecodeHelper.decodeDownsampledIfNeeded(
        at: fileURL, shortEdgePixels: shortEdgeCapPixels)
    }.value
    if let downsampled {
      logger.debug(
        "🔽 [Decode] Downsampled \(fileURL.lastPathComponent) to shortEdge≤\(Int(shortEdgeCapPixels))px"
      )
      return downsampled
    }

    let image = await Task.detached(priority: .userInitiated) {
      #if os(macOS)
        return NSImage(contentsOf: fileURL)
      #else
        return UIImage(contentsOfFile: fileURL.path)
      #endif
    }.value

    guard let image else { return nil }
    return await ImageDecodeHelper.decodeForDisplay(image)
  }

  private func loadPosterImageFromAnimatedFile(fileURL: URL) async -> PlatformImage? {
    let image = await Task.detached(priority: .userInitiated) { () -> PlatformImage? in
      AnimatedImageSupport.posterImage(from: fileURL)
    }.value

    guard let image else { return nil }
    return await ImageDecodeHelper.decodeForDisplay(image)
  }

  private func preloadDecodedPageImage(pageIndex: Int) async -> (
    image: PlatformImage?, animatedSourceFileURL: URL?, failure: ReaderPageLoadFailure?
  ) {
    guard let readerPage = readerPage(at: pageIndex) else {
      return (nil, nil, nil)
    }
    let page = readerPage.page

    let (sourceFileURL, failure) = await getPageImageFileURL(pageIndex: pageIndex)
    guard let sourceFileURL else {
      return (nil, nil, failure)
    }
    guard !Task.isCancelled else { return (nil, nil, nil) }

    let isAnimated = Self.detectAnimatedState(for: page, fileURL: sourceFileURL)
    let animatedSourceFileURL = isAnimated ? sourceFileURL : nil
    if isAnimated {
      if let posterImage = await loadPosterImageFromAnimatedFile(fileURL: sourceFileURL) {
        return (posterImage, animatedSourceFileURL, nil)
      }

      let fallbackImage = await loadImageFromFile(fileURL: sourceFileURL)
      return (fallbackImage, animatedSourceFileURL, nil)
    }

    let preferredFileURL = await preferredDisplayImageFileURL(
      page: page,
      pageID: readerPage.id,
      sourceFileURL: sourceFileURL,
      isAnimated: isAnimated
    )

    if let image = await loadImageFromFile(fileURL: preferredFileURL) {
      return (image, animatedSourceFileURL, nil)
    }

    if preferredFileURL != sourceFileURL {
      logger.debug(
        "⏭️ [Upscale] Fallback to original file for page \(page.number + 1) because @2x decode failed"
      )
      let fallbackImage = await loadImageFromFile(fileURL: sourceFileURL)
      return (fallbackImage, animatedSourceFileURL, nil)
    }

    return (nil, animatedSourceFileURL, nil)
  }

  private func preferredDisplayImageFileURL(
    page: BookPage,
    pageID: ReaderPageID,
    sourceFileURL: URL,
    isAnimated: Bool
  ) async -> URL {
    guard !isAnimated else { return sourceFileURL }

    let mode = AppConfig.imageUpscalingMode
    guard mode != .disabled else { return sourceFileURL }

    guard let sourcePixelSize = Self.sourcePixelSize(page: page, fileURL: sourceFileURL) else {
      logger.debug("⏭️ [Upscale] Skip page \(page.number + 1): unable to resolve source size")
      return sourceFileURL
    }

    let autoTriggerScale = CGFloat(AppConfig.imageUpscaleAutoTriggerScale)
    guard let screenPixelSize = mainScreenPixelSize else {
      logger.debug("⏭️ [Upscale] Skip page \(page.number + 1): unable to resolve current screen")
      return sourceFileURL
    }

    let decision = ReaderUpscaleDecision.evaluate(
      mode: mode,
      sourcePixelSize: sourcePixelSize,
      screenPixelSize: screenPixelSize,
      autoTriggerScale: autoTriggerScale
    )
    guard decision.shouldUpscale else {
      let skipReasonText = Self.upscaleSkipReasonText(decision.reason)
      logger.debug(
        String(
          format:
            "⏭️ [Upscale] Skip page %d: reason=%@ requiredScale=%.2f source=%dx%d screen=%dx%d auto=%.2f",
          page.number + 1,
          skipReasonText,
          decision.requiredScale,
          Int(sourcePixelSize.width),
          Int(sourcePixelSize.height),
          Int(screenPixelSize.width),
          Int(screenPixelSize.height),
          autoTriggerScale
        )
      )
      return sourceFileURL
    }

    let upscaledFileURLs = Self.upscaledImageFileURLs(from: sourceFileURL)
    if let cachedUpscaledURL = upscaledFileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
      logger.debug("✅ [Upscale] Use cached @2x page \(page.number + 1): \(cachedUpscaledURL.lastPathComponent)")
      return cachedUpscaledURL
    }

    if let existingTask = upscalingTasks[pageID] {
      logger.debug("⏳ [Upscale] Await running upscale task for page \(page.number + 1)")
      if let cachedURL = await existingTask.task.value {
        logger.debug("✅ [Upscale] Reuse task result for page \(page.number + 1): \(cachedURL.lastPathComponent)")
        return cachedURL
      }
      logger.debug("⏭️ [Upscale] Running task failed for page \(page.number + 1), use source")
      return sourceFileURL
    }

    let pageNumber = page.number
    logger.debug(
      String(
        format: "🚀 [Upscale] Queue page %d: mode=%@ requiredScale=%.2f source=%dx%d",
        pageNumber + 1,
        mode.rawValue,
        decision.requiredScale,
        Int(sourcePixelSize.width),
        Int(sourcePixelSize.height)
      )
    )

    let taskToken = UUID()
    let upscaleTask = Task<URL?, Never>.detached(priority: .userInitiated) {
      [sourceFileURL, upscaledFileURLs, pageNumber] in
      let logger = AppLogger(.reader)

      guard !Task.isCancelled else { return nil }

      if let cachedUpscaledURL = upscaledFileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        logger.debug("✅ [Upscale] Use cached @2x page \(pageNumber + 1): \(cachedUpscaledURL.lastPathComponent)")
        return cachedUpscaledURL
      }

      guard let sourceCGImage = Self.readCGImage(from: sourceFileURL) else {
        logger.debug("⏭️ [Upscale] Skip page \(pageNumber + 1): failed to decode source CGImage")
        return nil
      }

      let startedAt = Date()
      guard let output = await ReaderUpscaleModelManager.shared.process(sourceCGImage) else {
        logger.debug("⏭️ [Upscale] Skip page \(pageNumber + 1): model processing returned nil")
        return nil
      }
      guard !Task.isCancelled else { return nil }

      guard
        let persistedURL = Self.persistUpscaledCGImage(
          output,
          sourceFileURL: sourceFileURL,
          targetFileURLs: upscaledFileURLs,
          logger: logger
        )
      else {
        logger.error(
          "❌ [Upscale] Failed to save @2x page \(pageNumber + 1): source=\(sourceFileURL.lastPathComponent)"
        )
        return nil
      }

      let duration = Date().timeIntervalSince(startedAt)
      logger.debug(
        String(
          format: "💾 [Upscale] Saved page %d @2x in %.2fs -> %@",
          pageNumber + 1,
          duration,
          persistedURL.lastPathComponent
        )
      )
      return persistedURL
    }

    upscalingTasks[pageID] = TrackedTaskRecord(token: taskToken, task: upscaleTask)
    let result = await upscaleTask.value
    removeTrackedTaskIfCurrent(for: pageID, token: taskToken, from: &upscalingTasks)
    if let result {
      logger.debug("✅ [Upscale] Ready page \(pageNumber + 1): \(result.lastPathComponent)")
    } else {
      logger.debug("⏭️ [Upscale] Use source for page \(pageNumber + 1): @2x generation unavailable")
    }
    return result ?? sourceFileURL
  }

  nonisolated private static func sourcePixelSize(page: BookPage, fileURL: URL) -> CGSize? {
    if let width = page.width, let height = page.height, width > 0, height > 0 {
      return CGSize(width: width, height: height)
    }
    return ImageDecodeHelper.displayPixelSize(at: fileURL)
  }

  nonisolated private static func upscaledImageFileURLs(from sourceFileURL: URL) -> [URL] {
    let directory = sourceFileURL.deletingLastPathComponent()
    let baseName = sourceFileURL.deletingPathExtension().lastPathComponent
    let resolvedBaseName = baseName.hasSuffix("@2x") ? baseName : "\(baseName)@2x"

    let sourceExtension = sourceFileURL.pathExtension.lowercased()
    var candidates: [URL] = []

    if !sourceExtension.isEmpty {
      candidates.append(
        directory.appendingPathComponent(resolvedBaseName).appendingPathExtension(sourceExtension)
      )
    } else {
      candidates.append(directory.appendingPathComponent(resolvedBaseName))
    }

    if sourceExtension != "jpg" && sourceExtension != "jpeg" {
      candidates.append(
        directory.appendingPathComponent(resolvedBaseName).appendingPathExtension("jpg")
      )
    }
    if sourceExtension != "png" {
      candidates.append(
        directory.appendingPathComponent(resolvedBaseName).appendingPathExtension("png")
      )
    }

    var seenPaths = Set<String>()
    return candidates.filter { seenPaths.insert($0.path).inserted }
  }

  nonisolated private static func readCGImage(from fileURL: URL) -> CGImage? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, options)
  }

  nonisolated private static let supportedDestinationTypeIdentifiers: Set<String> = {
    let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    return Set(identifiers.map { $0.lowercased() })
  }()

  nonisolated private static func destinationUTType(for fileURL: URL) -> UTType? {
    let ext = fileURL.pathExtension.lowercased()
    guard !ext.isEmpty else { return nil }
    guard let type = UTType(filenameExtension: ext) else { return nil }
    guard supportedDestinationTypeIdentifiers.contains(type.identifier.lowercased()) else { return nil }
    return type
  }

  nonisolated private static func upscaleSkipReasonText(
    _ reason: ReaderUpscaleDecision.SkipReason?
  ) -> String {
    switch reason {
    case .disabled:
      return "disabled"
    case .belowAutoTriggerScale:
      return "below-auto-trigger-threshold"
    case .invalidSourceSize:
      return "invalid-source-size"
    case nil:
      return "unknown"
    }
  }

  nonisolated private static func persistUpscaledCGImage(
    _ image: CGImage,
    sourceFileURL: URL,
    targetFileURLs: [URL],
    logger: AppLogger
  ) -> URL? {
    let fileManager = FileManager.default
    guard let targetDirectory = targetFileURLs.first?.deletingLastPathComponent() else {
      logger.error("❌ [Upscale] No target path candidates for \(sourceFileURL.lastPathComponent)")
      return nil
    }

    do {
      try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    } catch {
      logger.error("❌ [Upscale] Failed to create target directory: \(targetDirectory.path)")
      return nil
    }

    for targetFileURL in targetFileURLs {
      guard let destinationType = destinationUTType(for: targetFileURL) else {
        logger.debug(
          "⏭️ [Upscale] Unsupported destination type for \(targetFileURL.lastPathComponent), trying fallback"
        )
        continue
      }

      guard
        let destination = CGImageDestinationCreateWithURL(
          targetFileURL as CFURL,
          destinationType.identifier as CFString,
          1,
          nil
        )
      else {
        logger.error(
          "❌ [Upscale] CGImageDestinationCreateWithURL failed: file=\(targetFileURL.lastPathComponent), type=\(destinationType.identifier)"
        )
        continue
      }

      CGImageDestinationAddImage(destination, image, nil)
      if CGImageDestinationFinalize(destination) {
        return targetFileURL
      }

      logger.error(
        "❌ [Upscale] CGImageDestinationFinalize failed: file=\(targetFileURL.lastPathComponent), type=\(destinationType.identifier)"
      )
    }

    return nil
  }

  private func updateAnimatedPresentation(
    knownAnimatedState: Bool?,
    sourceFileURL: URL?,
    for pageID: ReaderPageID
  ) {
    var didChange = false

    if let knownAnimatedState {
      if animatedPageStates[pageID] != knownAnimatedState {
        animatedPageStates[pageID] = knownAnimatedState
        didChange = true
      }
    } else if animatedPageStates.removeValue(forKey: pageID) != nil {
      didChange = true
    }

    if let sourceFileURL {
      if animatedPageSourceFileURLs[pageID] != sourceFileURL {
        animatedPageSourceFileURLs[pageID] = sourceFileURL
        didChange = true
      }
    } else if animatedPageSourceFileURLs.removeValue(forKey: pageID) != nil {
      didChange = true
    }

    if didChange {
      invalidatePresentation(.pages([pageID]))
    }
  }

  private func prepareAnimatedPagePlaybackURL(pageIndex: Int) async {
    guard pageIndex >= 0 && pageIndex < readerPages.count else { return }
    guard let pageID = readerPageID(forPageIndex: pageIndex) else { return }
    let page = readerPages[pageIndex].page
    guard page.isAnimatedImageCandidate else {
      updateAnimatedPresentation(knownAnimatedState: false, sourceFileURL: nil, for: pageID)
      return
    }

    guard let fileURL = await getPageImageFileURL(pageIndex: pageIndex).url else { return }
    let isAnimated = Self.detectAnimatedState(for: page, fileURL: fileURL)
    updateAnimatedPresentation(
      knownAnimatedState: isAnimated,
      sourceFileURL: isAnimated ? fileURL : nil,
      for: pageID
    )
  }

  private func resolvedDownloadURL(for page: BookPage, bookId: String) -> URL? {
    if let url = page.downloadURL {
      return url
    }
    return BookService.getBookPageURL(bookId: bookId, page: page.number)
  }
}

#if os(iOS) || os(tvOS)
  extension ReaderPageLoadScheduler: MemoryWarningListener {
    func handleMemoryWarning() {
      logger.warning("⚠️ [Reader/Memory] Received memory warning; pruning to visible pages only")
      pruneToVisiblePagesOnly()
    }
  }
#endif
