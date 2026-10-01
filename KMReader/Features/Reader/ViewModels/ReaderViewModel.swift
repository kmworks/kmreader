//
// ReaderViewModel.swift
//
//

import Foundation
import SwiftUI

@MainActor
@Observable
class ReaderViewModel {
  var readerPages: [ReaderPage] = []
  private(set) var segments: [ReaderSegment] = []
  var isolatePages: [Int] = []
  private var isolatePagesByBookId: [String: Set<Int>] = [:]
  private(set) var rotation: ReaderRotation
  private(set) var bookIdsWithMissingPageDimensions: Set<String> = []
  private var currentPageID: ReaderPageID?
  private var currentViewItemID: ReaderViewItem?
  // Last committed split side for the current page. A merge into `.both`
  // (e.g. rotation to dual layout) preserves it so a later rebuild can restore
  // the same split side instead of falling back to the first half.
  private var splitPartPreference: (pageID: ReaderPageID, part: ReaderSplitPart)?
  // Edges the committed whole spread rests at, as its page host last reported:
  // none between its edges, both when it fits the viewport.
  @ObservationIgnored
  private var wholeSpreadRestingEdges: (pageID: ReaderPageID, edges: Set<ReaderSpreadEdge>)?
  private(set) var navigationTarget: ReaderPositionAnchor?
  var isLoading = true
  var loadingTitle = String(localized: "Loading book...")
  var loadingDetail = String(localized: "Resolving page metadata")
  var loadingProgress: Double?
  var isDismissing = false
  /// Offline readiness of the next book relative to the segment being read.
  /// Surfaced on the end page so a slow download never looks like a dead tap,
  /// and a finished download reads as "ready" instead of going blank.
  private(set) var nextBookOfflineState: NextBookOfflineState?
  var incognitoMode: Bool = false
  var isZoomed: Bool = false

  var viewItems: [ReaderViewItem] = []
  var viewItemIndexByPage: [ReaderPageID: Int] = [:]
  var tableOfContents: [ReaderTOCEntry] = []
  private var tableOfContentsByBookId: [String: [ReaderTOCEntry]] = [:]
  private var tableOfContentsBookId: String?
  private var isolateCoverPageEnabled: Bool
  private var forceDualPagePairs: Bool
  private var splitWidePageMode: SplitWidePageMode
  private var pageTransitionStyle: PageTransitionStyle
  private var isActuallyUsingDualPageMode: Bool = false
  typealias PagePresentationInvalidationHandler = @MainActor (ReaderPagePresentationInvalidation) -> Void
  @ObservationIgnored
  private var pagePresentationInvalidationHandlers: [UUID: PagePresentationInvalidationHandler] = [:]
  @ObservationIgnored
  private var pdfPreparationTasks: [String: Task<Void, Never>] = [:]
  @ObservationIgnored
  private var progressDispatchTail: Task<Void, Never>?
  @ObservationIgnored
  private var sessionStartPagesByBookId: [String: Int] = [:]
  @ObservationIgnored
  private var progressRecordingGatesByBookId: [String: ReaderProgressRecordingGate] = [:]

  private enum SegmentFetchPurpose {
    case nextPreload
    case previousPreload

    var shouldEnsureOfflineReady: Bool {
      switch self {
      case .nextPreload:
        return true
      case .previousPreload:
        return false
      }
    }
  }

  private let logger = AppLogger(.reader)
  private let pageLoadScheduler: ReaderPageLoadScheduler
  private var bookMediaProfile: MediaProfile = .unknown

  private static func pdfPreparationTaskKey(instanceId: String, bookId: String) -> String {
    CompositeID.generate(instanceId: instanceId, id: bookId)
  }

  private var readerPageIndexByID: [ReaderPageID: Int] = [:]
  private var segmentPageRangeByBookId: [String: Range<Int>] = [:]
  private(set) var readerPagesVersion: Int = 0

  private var resolvedCurrentPageID: ReaderPageID? {
    if let currentPageID, readerPageIndexByID[currentPageID] != nil {
      return currentPageID
    }
    if let currentViewItemID,
      readerPageIndexByID[currentViewItemID.pageID] != nil
    {
      return currentViewItemID.pageID
    }
    return readerPages.first?.id
  }

  private var resolvedCurrentPageIndex: Int? {
    guard let resolvedCurrentPageID else { return nil }
    return readerPageIndexByID[resolvedCurrentPageID]
  }

  var currentPage: BookPage? {
    currentReaderPage?.page
  }

  var isShowingEndPage: Bool {
    currentViewItem()?.isEnd == true
  }

  var pageCount: Int {
    readerPages.count
  }

  var hasPages: Bool {
    !readerPages.isEmpty
  }

  var activeBookId: String? {
    currentReaderPage?.bookId ?? segments.first?.currentBook.id
  }

  var currentReaderPage: ReaderPage? {
    guard let resolvedCurrentPageIndex else { return nil }
    return readerPages[resolvedCurrentPageIndex]
  }

  var isCurrentPageIsolated: Bool {
    guard let currentReaderPage else { return false }
    guard let isolatePosition = isolatePosition(for: currentReaderPage.id) else { return false }
    return isolatePagesByBookId[currentReaderPage.bookId]?.contains(isolatePosition.localIndex) == true
  }

  func isPageIsolated(_ pageID: ReaderPageID) -> Bool {
    guard let isolatePosition = isolatePosition(for: pageID) else { return false }
    return isolatePagesByBookId[isolatePosition.bookId]?.contains(isolatePosition.localIndex) == true
  }

  func hasMissingPageDimensions(forBookId bookId: String) -> Bool {
    bookIdsWithMissingPageDimensions.contains(bookId)
  }

  func isPageEffectivelyPortrait(_ pageID: ReaderPageID) -> Bool {
    guard let page = readerPage(for: pageID)?.page,
      let width = page.width,
      let height = page.height
    else {
      return false
    }
    let size = rotation.rotatedSize(
      CGSize(width: CGFloat(width), height: CGFloat(height))
    )
    return size.height > size.width
  }

  /// Whether the current page is a wide (non-portrait) image, which cannot be isolated.
  var isCurrentPageWide: Bool {
    guard let currentReaderPage else { return false }
    return !isPageEffectivelyPortrait(currentReaderPage.id)
  }

  convenience init() {
    self.init(
      isolateCoverPage: AppConfig.isolateCoverPage,
      pageLayout: AppConfig.pageLayout,
      splitWidePageMode: AppConfig.splitWidePageMode,
      pageTransitionStyle: AppConfig.pageTransitionStyle,
      rotation: .none,
      preloadWindow: AppConfig.divinaPreloadProfile.window,
      incognitoMode: false
    )
  }

  init(
    isolateCoverPage: Bool,
    pageLayout: PageLayout,
    splitWidePageMode: SplitWidePageMode = .none,
    pageTransitionStyle: PageTransitionStyle = AppConfig.pageTransitionStyle,
    rotation: ReaderRotation = .none,
    preloadWindow: ReaderPreloadWindow = ReaderPreloadWindow.balanced,
    incognitoMode: Bool = false
  ) {
    self.pageLoadScheduler = ReaderPageLoadScheduler(preloadWindow: preloadWindow)
    self.isolateCoverPageEnabled = isolateCoverPage
    self.forceDualPagePairs = pageLayout == .dual
    self.splitWidePageMode = splitWidePageMode
    self.pageTransitionStyle = pageTransitionStyle
    self.rotation = rotation
    self.incognitoMode = incognitoMode
    pageLoadScheduler.setPresentationInvalidationHandler { [weak self] invalidation in
      self?.notifyPagePresentationInvalidation(invalidation)
    }
    regenerateViewState()
  }

  private func rebuildReaderPages() {
    var flattenedReaderPages: [ReaderPage] = []
    var indexMap: [ReaderPageID: Int] = [:]
    var rangeByBookId: [String: Range<Int>] = [:]

    flattenedReaderPages.reserveCapacity(segments.reduce(0) { $0 + $1.pages.count })

    var globalIndex = 0
    for segment in segments {
      let segmentStart = globalIndex
      for page in segment.pages {
        let readerPage = ReaderPage(bookId: segment.currentBook.id, page: page)
        flattenedReaderPages.append(readerPage)
        indexMap[readerPage.id] = globalIndex
        globalIndex += 1
      }
      rangeByBookId[segment.currentBook.id] = segmentStart..<globalIndex
    }

    readerPages = flattenedReaderPages
    readerPageIndexByID = indexMap
    segmentPageRangeByBookId = rangeByBookId
    pageLoadScheduler.updateReaderPages(flattenedReaderPages)
    readerPagesVersion &+= 1
    rebuildIsolatePageIndices()
  }

  private func rebuildIsolatePageIndices() {
    var flattenedIndices: [Int] = []
    flattenedIndices.reserveCapacity(isolatePagesByBookId.values.reduce(0) { $0 + $1.count })

    for (globalIndex, readerPage) in readerPages.enumerated() {
      guard let range = segmentPageRangeByBookId[readerPage.bookId], range.contains(globalIndex) else {
        continue
      }
      let localIndex = globalIndex - range.lowerBound
      if isolatePagesByBookId[readerPage.bookId]?.contains(localIndex) == true {
        flattenedIndices.append(globalIndex)
      }
    }

    isolatePages = flattenedIndices
  }

  private func isolatePosition(forGlobalPageIndex pageIndex: Int) -> (bookId: String, localIndex: Int)? {
    guard let readerPage = readerPage(at: pageIndex),
      let range = segmentPageRangeByBookId[readerPage.bookId],
      range.contains(pageIndex)
    else {
      return nil
    }
    return (readerPage.bookId, pageIndex - range.lowerBound)
  }

  private func isolatePosition(for pageID: ReaderPageID) -> (bookId: String, localIndex: Int)? {
    guard let pageIndex = pageIndex(for: pageID) else { return nil }
    return isolatePosition(forGlobalPageIndex: pageIndex)
  }

  private func matchingViewItem(
    preferredItem: ReaderViewItem? = nil,
    preferredPageID: ReaderPageID? = nil,
    preferredSplitPart: ReaderSplitPart? = nil
  ) -> ReaderViewItem? {
    if let preferredItem, viewItemIndex(for: preferredItem) != nil {
      return preferredItem
    }
    let resolvedPageID = preferredPageID ?? preferredItem?.pageID
    let splitPart = preferredSplitPart ?? splitPartPreference(forPageID: resolvedPageID)
    if let resolvedPageID, let splitPart {
      let splitItem = ReaderViewItem.split(id: resolvedPageID, part: splitPart)
      if viewItemIndex(for: splitItem) != nil {
        return splitItem
      }
    }
    if let preferredPageID, let resolvedItem = viewItem(for: preferredPageID) {
      return resolvedItem
    }
    if let preferredItem,
      let resolvedItem = viewItem(for: preferredItem.pageID)
    {
      return resolvedItem
    }
    return nil
  }

  private func splitPartPreference(forPageID pageID: ReaderPageID?) -> ReaderSplitPart? {
    guard let pageID, let splitPartPreference, splitPartPreference.pageID == pageID
    else { return nil }
    return splitPartPreference.part
  }

  private func preferredSplitPart(
    for item: ReaderViewItem,
    pageID: ReaderPageID?
  ) -> ReaderSplitPart? {
    if case .split(_, let part) = item, part != .both { return part }
    return splitPartPreference(forPageID: pageID ?? item.pageID)
  }

  private func resolvedViewItem(
    preferredItem: ReaderViewItem? = nil,
    preferredPageID: ReaderPageID? = nil
  ) -> ReaderViewItem? {
    matchingViewItem(
      preferredItem: preferredItem,
      preferredPageID: preferredPageID
    ) ?? viewItems.first
  }

  func updatePreloadWindow(_ preloadWindow: ReaderPreloadWindow) {
    pageLoadScheduler.updatePreloadWindow(preloadWindow)
  }

  func preloadedImage(for pageID: ReaderPageID) -> PlatformImage? {
    pageLoadScheduler.preloadedImage(for: pageID)
  }

  func getPageImageFileURL(pageID: ReaderPageID) async -> URL? {
    await pageLoadScheduler.getPageImageFileURL(pageID: pageID)
  }

  func addPagePresentationInvalidationObserver(
    _ handler: @escaping PagePresentationInvalidationHandler
  ) -> UUID {
    let token = UUID()
    pagePresentationInvalidationHandlers[token] = handler
    return token
  }

  func removePagePresentationInvalidationObserver(_ token: UUID) {
    pagePresentationInvalidationHandlers.removeValue(forKey: token)
  }

  private func notifyPagePresentationInvalidation(
    _ invalidation: ReaderPagePresentationInvalidation
  ) {
    for handler in pagePresentationInvalidationHandlers.values {
      handler(invalidation)
    }
  }

  private func readerPage(at pageIndex: Int) -> ReaderPage? {
    guard pageIndex >= 0, pageIndex < readerPages.count else { return nil }
    return readerPages[pageIndex]
  }

  func readerPage(for pageID: ReaderPageID) -> ReaderPage? {
    guard let pageIndex = pageIndex(for: pageID) else { return nil }
    return readerPage(at: pageIndex)
  }

  func page(for pageID: ReaderPageID) -> BookPage? {
    readerPage(for: pageID)?.page
  }

  private func pageWindowEntries(around pageID: ReaderPageID?, before: Int, after: Int)
    -> [(index: Int, pageID: ReaderPageID)]
  {
    guard let pageID, let centerIndex = pageIndex(for: pageID), !readerPages.isEmpty else { return [] }
    let safeBefore = max(before, 0)
    let safeAfter = max(after, 0)
    let upperBound = max(pageCount - 1, 0)
    let lowerIndex = max(centerIndex - safeBefore, 0)
    let upperIndex = min(centerIndex + safeAfter, upperBound)
    guard lowerIndex <= upperIndex else { return [] }
    return readerPages[lowerIndex...upperIndex].enumerated().map { offset, readerPage in
      (index: lowerIndex + offset, pageID: readerPage.id)
    }
  }

  func neighboringPageIDs(around pageID: ReaderPageID, radius: Int) -> [ReaderPageID] {
    pageWindowEntries(around: pageID, before: radius, after: radius).map(\.pageID)
  }

  func hasPendingImageLoad(for pageID: ReaderPageID) -> Bool {
    pageLoadScheduler.hasPendingImageLoad(for: pageID)
  }

  func hasFailedImageLoad(for pageID: ReaderPageID) -> Bool {
    pageLoadScheduler.hasFailedImageLoad(for: pageID)
  }

  func imageLoadFailure(for pageID: ReaderPageID) -> ReaderPageLoadFailure? {
    pageLoadScheduler.imageLoadFailure(for: pageID)
  }

  func retryImageLoad(for pageID: ReaderPageID) {
    pageLoadScheduler.retryImageLoad(for: pageID)
  }

  func prioritizeVisiblePageLoads(for pageIDs: [ReaderPageID]) {
    pageLoadScheduler.prioritizeVisiblePageLoads(for: pageIDs)
  }

  func pageIndex(for readerPageID: ReaderPageID) -> Int? {
    readerPageIndexByID[readerPageID]
  }

  private func segmentIndex(forSegmentBookId bookId: String) -> Int? {
    segments.firstIndex(where: { $0.currentBook.id == bookId })
  }

  func nextBook(forSegmentBookId bookId: String) -> Book? {
    guard let segmentIndex = segmentIndex(forSegmentBookId: bookId) else { return nil }
    return segments[segmentIndex].nextBook
  }

  /// Offline state for the segment's next book: live download progress while a
  /// next-segment preload is blocked, then "ready" once it is available offline
  /// (also when it was already downloaded before the preload ran).
  func nextBookOfflineState(forSegmentBookId bookId: String) -> NextBookOfflineState? {
    guard let nextBookOfflineState,
      let nextBook = nextBook(forSegmentBookId: bookId)
    else {
      return nil
    }
    switch nextBookOfflineState {
    case .downloading(let stateBookId, _), .ready(let stateBookId):
      guard nextBook.id == stateBookId else { return nil }
    }
    return nextBookOfflineState
  }

  func currentBook(forSegmentBookId bookId: String) -> Book? {
    guard let segmentIndex = segmentIndex(forSegmentBookId: bookId) else { return nil }
    return segments[segmentIndex].currentBook
  }

  func previousBook(forSegmentBookId bookId: String) -> Book? {
    guard let segmentIndex = segmentIndex(forSegmentBookId: bookId) else { return nil }
    return segments[segmentIndex].previousBook
  }

  /// End page is rendered between the finished segment book and its next sibling.
  /// The leading "previous" slot intentionally shows the finished/current segment book.
  func endPagePreviousBook(forSegmentBookId bookId: String) -> Book? {
    currentBook(forSegmentBookId: bookId)
  }

  private func segmentPageRange(forSegmentBookId bookId: String) -> Range<Int>? {
    segmentPageRangeByBookId[bookId]
  }

  func segmentReaderPages(forSegmentBookId bookId: String) -> [ReaderPage] {
    guard let range = segmentPageRange(forSegmentBookId: bookId) else { return [] }
    return Array(readerPages[range])
  }

  func pageID(forSegmentBookId bookId: String, pageNumberInSegment pageNumber: Int) -> ReaderPageID? {
    guard let range = segmentPageRange(forSegmentBookId: bookId), !range.isEmpty else { return nil }
    let localIndex = pageNumber - 1
    guard localIndex >= 0 && localIndex < range.count else { return nil }
    return readerPages[range.lowerBound + localIndex].id
  }

  func lastPageID(forSegmentBookId bookId: String) -> ReaderPageID? {
    guard let range = segmentPageRange(forSegmentBookId: bookId), !range.isEmpty else { return nil }
    return readerPages[range.upperBound - 1].id
  }

  func pageCount(forSegmentBookId bookId: String) -> Int {
    segmentPageRange(forSegmentBookId: bookId)?.count ?? 0
  }

  func displayPageNumber(for pageID: ReaderPageID) -> Int? {
    guard let readerPage = readerPage(for: pageID) else { return nil }
    let offset = displayPageNumberOffset(forBookId: readerPage.bookId)
    return readerPage.page.number + offset
  }

  private func displayPageNumberOffset(forBookId bookId: String) -> Int {
    guard let range = segmentPageRangeByBookId[bookId],
      let firstPageNumber = readerPage(at: range.lowerBound)?.page.number
    else {
      return 1
    }
    return firstPageNumber == 0 ? 1 : 0
  }

  func activeSegmentContext(
    fallbackBookId: String,
    fallbackCurrentBook: Book?,
    fallbackPreviousBook: Book?,
    fallbackNextBook: Book?
  ) -> (bookId: String, currentBook: Book?, previousBook: Book?, nextBook: Book?) {
    let segmentBookId = currentReaderPage?.bookId ?? fallbackBookId
    let shouldUseFallback = segmentBookId == fallbackBookId

    let segmentCurrentBook = currentBook(forSegmentBookId: segmentBookId)
    let segmentPreviousBook = previousBook(forSegmentBookId: segmentBookId)
    let segmentNextBook = nextBook(forSegmentBookId: segmentBookId)

    return (
      bookId: segmentBookId,
      currentBook: segmentCurrentBook ?? (shouldUseFallback ? fallbackCurrentBook : nil),
      previousBook: segmentPreviousBook ?? (shouldUseFallback ? fallbackPreviousBook : nil),
      nextBook: segmentNextBook ?? (shouldUseFallback ? fallbackNextBook : nil)
    )
  }

  func currentPageNumber(inSegmentBookId bookId: String) -> Int? {
    guard let currentPageOffset = currentPageOffsetInSegment(for: bookId) else { return nil }
    return currentPageOffset + 1
  }

  func currentPageOffsetInSegment(for bookId: String) -> Int? {
    guard let currentReaderPage,
      currentReaderPage.bookId == bookId,
      let range = segmentPageRangeByBookId[bookId],
      let currentPageIndex = pageIndex(for: currentReaderPage.id),
      range.contains(currentPageIndex)
    else {
      return nil
    }
    return currentPageIndex - range.lowerBound
  }

  func remainingPagesInSegment(for bookId: String) -> Int? {
    guard let currentPageOffset = currentPageOffsetInSegment(for: bookId),
      let range = segmentPageRangeByBookId[bookId]
    else {
      return nil
    }
    return max(range.count - currentPageOffset - 1, 0)
  }

  func currentTOCSelection(in entries: [ReaderTOCEntry], for bookId: String) -> ReaderTOCSelection {
    guard let currentPageOffset = currentPageOffsetInSegment(for: bookId) else {
      return .empty
    }
    return ReaderTOCSelection.resolve(in: entries, currentPageIndex: currentPageOffset)
  }

  private func setTableOfContents(_ toc: [ReaderTOCEntry], for bookId: String) {
    tableOfContentsByBookId[bookId] = toc
    tableOfContents = toc
    tableOfContentsBookId = bookId
  }

  private func loadTableOfContentsFromStorageOrNetwork(for book: Book) async -> [ReaderTOCEntry] {
    let mediaProfile = book.media.mediaProfileValue ?? .unknown
    let database = await DatabaseOperator.databaseIfConfigured()

    if mediaProfile == .epub {
      if let localTOC = await database?.fetchTOC(id: book.id) {
        return localTOC
      }
      if !AppConfig.isOffline {
        do {
          let manifest = try await BookService.getBookManifest(id: book.id)
          let toc = await ReaderManifestService(bookId: book.id).parseTOC(manifest: manifest)
          await database?.updateBookTOC(bookId: book.id, toc: toc)
          return toc
        } catch {
          logger.error("❌ Failed to load TOC from manifest for book \(book.id): \(error)")
          return []
        }
      }
      return []
    }

    if mediaProfile == .pdf {
      return await database?.fetchTOC(id: book.id) ?? []
    }

    return []
  }

  func ensureTableOfContentsLoaded(for book: Book) async {
    if let cachedTOC = tableOfContentsByBookId[book.id] {
      setTableOfContents(cachedTOC, for: book.id)
      return
    }

    let toc = await loadTableOfContentsFromStorageOrNetwork(for: book)
    setTableOfContents(toc, for: book.id)
  }

  func ensureTableOfContentsForCurrentSegment() async {
    guard let currentReaderPage else { return }
    let segmentBookId = currentReaderPage.bookId

    guard tableOfContentsBookId != segmentBookId else { return }
    guard let segmentBook = currentBook(forSegmentBookId: segmentBookId) else {
      tableOfContents = []
      tableOfContentsBookId = segmentBookId
      return
    }

    await ensureTableOfContentsLoaded(for: segmentBook)
  }

  private func setSegments(_ segments: [ReaderSegment]) {
    self.segments = segments
    rebuildReaderPages()
  }

  private func updateSegmentContext(
    forCurrentBookId currentBookId: String,
    previousBook: Book?,
    nextBook: Book?
  ) {
    guard let segmentIndex = segmentIndex(forSegmentBookId: currentBookId) else {
      return
    }
    let segment = segments[segmentIndex]
    segments[segmentIndex] = ReaderSegment(
      previousBook: previousBook,
      currentBook: segment.currentBook,
      nextBook: nextBook,
      pages: segment.pages
    )
  }

  /// Update the adjacent-book metadata for an existing segment. Called when the
  /// reader's deferred adjacent-book fetch resolves so the segment's
  /// `previousBook`/`nextBook` reflect the freshly-fetched values, preventing
  /// redundant re-fetches from later code paths such as `resolveSegmentPreloadContext`
  /// that read these from the segment.
  ///
  /// No-op when no segment matches `bookId` — e.g., the user has navigated away
  /// before the deferred fetch resolved.
  func updateAdjacentBooksForSegment(
    bookId: String,
    previousBook: Book?,
    nextBook: Book?
  ) {
    updateSegmentContext(
      forCurrentBookId: bookId,
      previousBook: previousBook,
      nextBook: nextBook
    )
  }

  private func appendSegment(
    currentBook: Book,
    previousBook: Book?,
    nextBook: Book?,
    pages: [BookPage]
  ) {
    segments.append(
      ReaderSegment(
        previousBook: previousBook,
        currentBook: currentBook,
        nextBook: nextBook,
        pages: pages
      ))
    rebuildReaderPages()
  }

  private func prependSegment(
    currentBook: Book,
    previousBook: Book?,
    nextBook: Book?,
    pages: [BookPage]
  ) {
    segments.insert(
      ReaderSegment(
        previousBook: previousBook,
        currentBook: currentBook,
        nextBook: nextBook,
        pages: pages
      ),
      at: 0
    )
    rebuildReaderPages()
  }

  private func fetchSegmentPages(for book: Book, purpose: SegmentFetchPurpose) async -> [BookPage]? {
    let database = await DatabaseOperator.databaseIfConfigured()
    let fetchedPages: [BookPage]
    let shouldRefreshCachedPages: Bool

    if AppConfig.offlineFirstReading, purpose.shouldEnsureOfflineReady {
      do {
        try await ensureOfflineReady(book: book, updatesLoadingState: false)
      } catch {
        logger.error("❌ Failed to prepare offline segment for book \(book.id): \(error)")
        return nil
      }

      guard let localPages = await database?.fetchPages(id: book.id) else {
        return nil
      }
      fetchedPages = localPages
      shouldRefreshCachedPages = false
    } else if let cachedPages = await database?.fetchPages(id: book.id) {
      fetchedPages = cachedPages
      shouldRefreshCachedPages = !AppConfig.offlineFirstReading && !AppConfig.isOffline
    } else {
      guard !AppConfig.isOffline else {
        return nil
      }

      do {
        fetchedPages = try await BookService.getBookPages(id: book.id)
        await database?.updateBookPages(bookId: book.id, pages: fetchedPages)
        shouldRefreshCachedPages = false
      } catch {
        logger.error("❌ Failed to preload segment pages for book \(book.id): \(error)")
        return nil
      }
    }

    return await resolvePageDimensions(
      bookId: book.id,
      pages: fetchedPages,
      shouldRefreshCachedPages: shouldRefreshCachedPages
    )
  }

  private func resolvePageDimensions(
    bookId: String,
    pages: [BookPage],
    shouldRefreshCachedPages: Bool
  ) async -> [BookPage] {
    var resolvedPages = pages

    if shouldRefreshCachedPages,
      resolvedPages.contains(where: { !$0.hasValidDimensions })
    {
      do {
        let refreshedPages = try await BookService.getBookPages(id: bookId)
        resolvedPages = preservingKnownDimensions(
          in: refreshedPages,
          from: resolvedPages
        )
        if let database = await DatabaseOperator.databaseIfConfigured() {
          await database.updateBookPages(bookId: bookId, pages: resolvedPages)
        }
      } catch {
        logger.warning(
          "⚠️ Failed to refresh page dimensions from server for book \(bookId): \(error)"
        )
      }
    }

    if resolvedPages.contains(where: { !$0.hasValidDimensions }) {
      resolvedPages = await OfflineManager.shared.fillMissingPageDimensions(
        instanceId: AppConfig.current.instanceId,
        bookId: bookId,
        pages: resolvedPages
      )
    }

    updateMissingPageDimensionsState(bookId: bookId, pages: resolvedPages)
    return resolvedPages
  }

  private func preservingKnownDimensions(
    in refreshedPages: [BookPage],
    from cachedPages: [BookPage]
  ) -> [BookPage] {
    let cachedDimensionsByFileName = cachedPages.reduce(into: [String: (width: Int, height: Int)]()) {
      result, page in
      guard page.hasValidDimensions, let width = page.width, let height = page.height else { return }
      result[page.fileName] = (width, height)
    }

    return refreshedPages.map { page in
      guard !page.hasValidDimensions,
        let dimensions = cachedDimensionsByFileName[page.fileName]
      else {
        return page
      }
      return page.withDimensions(width: dimensions.width, height: dimensions.height)
    }
  }

  private func updateMissingPageDimensionsState(bookId: String, pages: [BookPage]) {
    let hasMissingDimensions = pages.contains(where: { !$0.hasValidDimensions })
    if hasMissingDimensions {
      guard !bookIdsWithMissingPageDimensions.contains(bookId) else { return }
      bookIdsWithMissingPageDimensions.insert(bookId)
    } else {
      guard bookIdsWithMissingPageDimensions.contains(bookId) else { return }
      bookIdsWithMissingPageDimensions.remove(bookId)
    }
  }

  private func hydrateIsolatePages(for bookId: String) async {
    let database = await DatabaseOperator.databaseIfConfigured()
    let isolatePagesForBook = await database?.fetchIsolatePages(id: bookId) ?? []
    isolatePagesByBookId[bookId] = Set(isolatePagesForBook)
  }

  private func syncPageLoadSchedulerCurrentPage() {
    pageLoadScheduler.updateCurrentPageID(resolvedCurrentPageID)
  }

  private func resetStateForBookLoad() {
    pageLoadScheduler.resetForBookLoad()
    isolatePages.removeAll()
    isolatePagesByBookId.removeAll()
    bookIdsWithMissingPageDimensions.removeAll()
    tableOfContents.removeAll()
    tableOfContentsByBookId.removeAll()
    tableOfContentsBookId = nil
    segments.removeAll()
    readerPages.removeAll()
    viewItems.removeAll()
    viewItemIndexByPage.removeAll()
    readerPageIndexByID.removeAll()
    segmentPageRangeByBookId.removeAll()
    currentPageID = nil
    currentViewItemID = nil
    navigationTarget = nil
    nextBookOfflineState = nil
    sessionStartPagesByBookId.removeAll()
    progressRecordingGatesByBookId.removeAll()
    readerPagesVersion &+= 1
  }

  func preloadNextSegmentIfNeeded(
    currentBook: Book,
    previousBook: Book?,
    nextBook: Book?
  ) async {
    updateSegmentContext(
      forCurrentBookId: currentBook.id,
      previousBook: previousBook,
      nextBook: nextBook
    )

    guard let nextBook else {
      regenerateViewState()
      return
    }
    guard !segments.contains(where: { $0.currentBook.id == nextBook.id }) else {
      regenerateViewState()
      return
    }

    guard let fetchedPages = await fetchSegmentPages(for: nextBook, purpose: .nextPreload) else {
      regenerateViewState()
      return
    }

    guard !fetchedPages.isEmpty else {
      regenerateViewState()
      return
    }

    await hydrateIsolatePages(for: nextBook.id)
    let positionAnchor = captureCurrentPositionAnchor()

    appendSegment(
      currentBook: nextBook,
      previousBook: currentBook,
      nextBook: nil,
      pages: fetchedPages
    )
    regenerateViewState(preserving: positionAnchor)
  }

  func preloadPreviousSegmentIfNeeded(
    currentBook: Book,
    previousBook: Book?,
    nextBook: Book?,
    previousPreviousBook: Book?
  ) async {
    updateSegmentContext(
      forCurrentBookId: currentBook.id,
      previousBook: previousBook,
      nextBook: nextBook
    )

    guard let previousBook else {
      regenerateViewState()
      return
    }
    guard !segments.contains(where: { $0.currentBook.id == previousBook.id }) else {
      regenerateViewState()
      return
    }

    guard let fetchedPages = await fetchSegmentPages(for: previousBook, purpose: .previousPreload) else {
      regenerateViewState()
      return
    }

    guard !fetchedPages.isEmpty else {
      regenerateViewState()
      return
    }

    await hydrateIsolatePages(for: previousBook.id)
    let positionAnchor = captureCurrentPositionAnchor()

    prependSegment(
      currentBook: previousBook,
      previousBook: previousPreviousBook,
      nextBook: currentBook,
      pages: fetchedPages
    )
    regenerateViewState(preserving: positionAnchor)
  }

  func loadPages(
    book: Book,
    initialPageNumber: Int? = nil,
    previousBook: Book? = nil,
    nextBook: Book? = nil
  ) async {
    self.bookMediaProfile = book.media.mediaProfileValue ?? .unknown
    isLoading = true
    loadingTitle = String(localized: "Loading book...")
    loadingDetail = String(localized: "Resolving page metadata")
    loadingProgress = nil

    resetStateForBookLoad()

    do {
      if AppConfig.offlineFirstReading {
        try await ensureOfflineReady(book: book, updatesLoadingState: true)
      }
      await ensureOfflinePDFMetadataForDivina(book: book)
      let database = await DatabaseOperator.databaseIfConfigured()

      let storedPages: [BookPage]
      let shouldRefreshCachedPages: Bool
      if let localPages = await database?.fetchPages(id: book.id) {
        storedPages = localPages
        shouldRefreshCachedPages = !AppConfig.offlineFirstReading && !AppConfig.isOffline
      } else if !AppConfig.isOffline {
        storedPages = try await BookService.getBookPages(id: book.id)
        await database?.updateBookPages(bookId: book.id, pages: storedPages)
        shouldRefreshCachedPages = false
      } else {
        throw APIError.offline
      }
      let fetchedPages = await resolvePageDimensions(
        bookId: book.id,
        pages: storedPages,
        shouldRefreshCachedPages: shouldRefreshCachedPages
      )

      let localIsolatePages = await database?.fetchIsolatePages(id: book.id) ?? []
      isolatePagesByBookId[book.id] = Set(localIsolatePages)
      currentPageID = initialPageNumber.flatMap { pageNumber in
        fetchedPages.first(where: { $0.number == pageNumber }).map {
          ReaderPageID(bookId: book.id, pageNumber: $0.number)
        }
      }
      currentViewItemID = nil
      navigationTarget = nil

      setSegments([
        ReaderSegment(
          previousBook: previousBook,
          currentBook: book,
          nextBook: nextBook,
          pages: fetchedPages,
        )
      ])

      // Update page pairs and dual page indices after loading pages
      regenerateViewState()
      await ensureTableOfContentsLoaded(for: book)
      startBackgroundOfflinePDFPreparationIfNeeded(book: book)
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    isLoading = false
  }

  private func ensureOfflineReady(book: Book, updatesLoadingState: Bool) async throws {
    let downloadInfo = book.downloadInfo
    let status = await OfflineManager.shared.getDownloadStatus(bookId: book.id)
    if case .downloaded = status {
      if updatesLoadingState {
        updateLoadingProgress(ReaderLoadingProgress.complete)
        updateLoadingDetail(String(localized: "Using downloaded book files"))
      } else {
        updateNextBookOfflineState(.ready(bookId: book.id))
      }
      return
    }
    defer { clearDownloadingNextBook(bookId: book.id) }

    if AppConfig.isOffline {
      throw AppErrorType.networkUnavailable
    }

    if updatesLoadingState {
      updateLoadingTitle(String(localized: "Downloading book..."))
      updateLoadingDetail(String(localized: "Preparing offline download"))
      clearLoadingProgress()
    }

    switch status {
    case .notDownloaded, .failed, .pending:
      await OfflineManager.shared.downloadForReading(
        instanceId: AppConfig.current.instanceId,
        info: downloadInfo
      )
      updateNextBookOfflineState(.downloading(bookId: book.id, progress: nil))
    case .downloaded:
      updateLoadingProgress(ReaderLoadingProgress.complete)
      updateLoadingDetail(String(localized: "Using downloaded book files"))
      return
    }

    while true {
      if AppConfig.isOffline {
        throw AppErrorType.networkUnavailable
      }

      let currentStatus = await OfflineManager.shared.getDownloadStatus(bookId: book.id)
      switch currentStatus {
      case .downloaded:
        if updatesLoadingState {
          updateLoadingProgress(ReaderLoadingProgress.complete)
          updateLoadingDetail(String(localized: "Using downloaded book files"))
        } else {
          updateNextBookOfflineState(.ready(bookId: book.id))
        }
        return
      case .failed(let error):
        throw AppErrorType.operationFailed(message: error)
      case .notDownloaded:
        throw AppErrorType.operationFailed(
          message: String(localized: "Download did not start. Please try again.")
        )
      case .pending:
        let progress = DownloadProgressTracker.shared.progress[book.id]
        updateNextBookOfflineState(.downloading(bookId: book.id, progress: progress))
        if updatesLoadingState,
          let progress
        {
          if progress >= 1 {
            updateLoadingProgress(ReaderLoadingProgress.complete)
            let status = offlinePostDownloadStatus(for: downloadInfo.kind)
            updateLoadingTitle(status.title)
            updateLoadingDetail(status.detail)
          } else if progress > 0 {
            updateLoadingProgress(progress)
            updateLoadingTitle(String(localized: "Downloading book..."))
            updateLoadingDetail(String(localized: "Downloading book content"))
          } else {
            clearLoadingProgress()
            updateLoadingTitle(String(localized: "Downloading book..."))
            updateLoadingDetail(String(localized: "Waiting for offline download to start"))
          }
        }
      }

      try await Task.sleep(for: .milliseconds(200))
    }
  }

  private func updateNextBookOfflineState(_ state: NextBookOfflineState) {
    guard nextBookOfflineState != state else { return }
    nextBookOfflineState = state
    notifyPagePresentationInvalidation(.all)
  }

  /// Clears a stale in-flight download marker on the preload error paths. A
  /// published `.ready` state is kept: the end page should keep showing
  /// "ready" until the reader moves on to another book.
  private func clearDownloadingNextBook(bookId: String) {
    guard case .downloading(let stateBookId, _) = nextBookOfflineState,
      stateBookId == bookId
    else {
      return
    }
    nextBookOfflineState = nil
    notifyPagePresentationInvalidation(.all)
  }

  private func ensureOfflinePDFMetadataForDivina(book: Book) async {
    guard bookMediaProfile == .pdf else {
      return
    }

    let instanceId = AppConfig.current.instanceId
    guard
      let offlinePDFURL = await OfflineManager.shared.getOfflinePDFURL(
        instanceId: instanceId,
        bookId: book.id
      )
    else {
      logger.debug("⏭️ Skip offline PDF preparation because offline PDF file is missing for book \(book.id)")
      return
    }

    let database = await DatabaseOperator.databaseIfConfigured()
    let localPages = await database?.fetchPages(id: book.id, instanceId: instanceId)
    let localTOC = await database?.fetchTOC(id: book.id, instanceId: instanceId)
    let hasLocalPages = !(localPages ?? []).isEmpty
    let hasLocalTOC = localTOC != nil
    guard !hasLocalPages || !hasLocalTOC else { return }

    updateLoadingTitle(String(localized: "Preparing PDF..."))
    updateLoadingDetail(String(localized: "Checking PDF download information"))

    logger.debug(
      "🧪 Loading PDF metadata for DIVINA reader, book \(book.id), hasPages=\(hasLocalPages), hasTOC=\(hasLocalTOC)"
    )

    guard
      let metadata = await PdfOfflinePreparationService.shared.loadMetadata(
        documentURL: offlinePDFURL
      )
    else {
      logger.debug("⏭️ Skip PDF metadata load because local PDF cannot be opened for book \(book.id)")
      return
    }

    if !hasLocalPages {
      await database?.updateBookPages(bookId: book.id, instanceId: instanceId, pages: metadata.pages)
    }
    if !hasLocalTOC {
      await database?.updateBookTOC(bookId: book.id, instanceId: instanceId, toc: metadata.tableOfContents)
    }
  }

  private func startBackgroundOfflinePDFPreparationIfNeeded(book: Book) {
    guard bookMediaProfile == .pdf else {
      return
    }

    let instanceId = AppConfig.current.instanceId
    let taskKey = Self.pdfPreparationTaskKey(instanceId: instanceId, bookId: book.id)
    guard pdfPreparationTasks[taskKey] == nil else { return }

    pdfPreparationTasks[taskKey] = Task { [weak self] in
      guard let self else { return }
      await self.prepareOfflinePDFForDivinaInBackground(book: book, instanceId: instanceId)
      self.pdfPreparationTasks[taskKey] = nil
    }
  }

  private func prepareOfflinePDFForDivinaInBackground(book: Book, instanceId: String) async {
    guard bookMediaProfile == .pdf else {
      return
    }

    logger.debug("🧪 Preparing offline PDF assets for DIVINA reader, book \(book.id)")

    guard
      let offlinePDFURL = await OfflineManager.shared.getOfflinePDFURL(
        instanceId: instanceId,
        bookId: book.id
      )
    else {
      logger.debug("⏭️ Skip offline PDF preparation because offline PDF file is missing for book \(book.id)")
      return
    }

    let database = await DatabaseOperator.databaseIfConfigured()
    let localPages = await database?.fetchPages(id: book.id, instanceId: instanceId)
    let localTOC = await database?.fetchTOC(id: book.id, instanceId: instanceId)
    let hasLocalPages = !(localPages ?? []).isEmpty
    let hasLocalTOC = localTOC != nil
    let forceRebuildMetadata = !hasLocalPages || !hasLocalTOC
    if forceRebuildMetadata {
      logger.debug(
        "🛠️ Force PDF metadata rebuild for book \(book.id), hasPages=\(hasLocalPages), hasTOC=\(hasLocalTOC)"
      )
    }

    guard
      let result = await PdfOfflinePreparationService.shared.prepare(
        instanceId: instanceId,
        bookId: book.id,
        documentURL: offlinePDFURL,
        forceRebuildMetadata: forceRebuildMetadata
      )
    else {
      logger.debug("⏭️ Skip offline PDF preparation because assets are already valid for book \(book.id)")
      return
    }

    await applyPreparedPDFMetadata(bookId: book.id, instanceId: instanceId, result: result)
  }

  private func updateLoadingTitle(_ title: String) {
    guard loadingTitle != title else { return }
    loadingTitle = title
  }

  private func offlinePostDownloadStatus(for kind: DownloadContentKind) -> (
    title: String, detail: String
  ) {
    switch kind {
    case .archiveImages:
      return (
        String(localized: "Validating offline archive..."),
        String(localized: "Checking archive entries against page metadata")
      )
    case .epubWebPub, .epubDivina:
      return (
        String(localized: "Finalizing offline EPUB..."),
        String(localized: "Saving downloaded EPUB for offline reading")
      )
    case .pdf:
      return (
        String(localized: "Finalizing offline PDF..."),
        String(localized: "Saving downloaded PDF for offline reading")
      )
    case .pages:
      return (
        String(localized: "Finalizing offline pages..."),
        String(localized: "Saving downloaded page files")
      )
    }
  }

  private func updateLoadingDetail(_ detail: String) {
    guard loadingDetail != detail else { return }
    loadingDetail = detail
  }

  private func updateLoadingProgress(_ progress: Double) {
    let displayProgress = ReaderLoadingProgress.displayValue(for: progress)
    guard loadingProgress != displayProgress else { return }
    loadingProgress = displayProgress
  }

  private func clearLoadingProgress() {
    guard loadingProgress != nil else { return }
    loadingProgress = nil
  }

  private func applyPreparedPDFMetadata(
    bookId: String,
    instanceId: String,
    result: PdfOfflinePreparationService.PreparationResult
  ) async {
    logger.debug(
      "💾 Applying prepared PDF metadata to database for book \(bookId), pages=\(result.pages.count), toc=\(result.tableOfContents.count)"
    )

    if let database = await DatabaseOperator.databaseIfConfigured() {
      await database.updateBookPages(bookId: bookId, instanceId: instanceId, pages: result.pages)
      await database.updateBookTOC(bookId: bookId, instanceId: instanceId, toc: result.tableOfContents)
    }
    if result.renderedImageCount > 0 {
      await OfflineManager.shared.refreshDownloadedBookSize(
        instanceId: instanceId,
        bookId: bookId
      )
    } else {
      logger.debug("⏭️ Skip downloaded size refresh for book \(bookId) because no new PDF page was rendered")
    }

    guard AppConfig.current.instanceId == instanceId else {
      logger.debug(
        "⏭️ Skip applying prepared PDF metadata to visible reader because active instance changed for book \(bookId)"
      )
      return
    }

    if result.rerenderedImages {
      pageLoadScheduler.discardPreloadedImages(forBookId: bookId)
    }

    replaceLoadedSegmentPages(bookId: bookId, pages: result.pages)
    updateLoadedTableOfContents(bookId: bookId, tableOfContents: result.tableOfContents)

    logger.debug(
      "✅ Applied prepared PDF metadata for book \(bookId), rendered=\(result.renderedImageCount), reused=\(result.reusedImageCount), skipped=\(result.skippedImageCount)"
    )
  }

  private func replaceLoadedSegmentPages(bookId: String, pages: [BookPage]) {
    guard !pages.isEmpty else { return }
    guard let segmentIndex = segmentIndex(forSegmentBookId: bookId) else { return }

    let segment = segments[segmentIndex]
    let positionAnchor = captureCurrentPositionAnchor()
    segments[segmentIndex] = ReaderSegment(
      previousBook: segment.previousBook,
      currentBook: segment.currentBook,
      nextBook: segment.nextBook,
      pages: pages
    )
    rebuildReaderPages()
    regenerateViewState(preserving: positionAnchor)
    notifyPagePresentationInvalidation(.all)
  }

  private func updateLoadedTableOfContents(
    bookId: String,
    tableOfContents: [ReaderTOCEntry]
  ) {
    tableOfContentsByBookId[bookId] = tableOfContents
    if activeBookId == bookId || tableOfContentsBookId == bookId {
      setTableOfContents(tableOfContents, for: bookId)
    }
  }

  func preloadPages(bypassThrottle: Bool = false) async {
    syncPageLoadSchedulerCurrentPage()
    await pageLoadScheduler.preloadPages(bypassThrottle: bypassThrottle)
  }

  func cleanupDistantImagesAroundCurrentPage() {
    syncPageLoadSchedulerCurrentPage()
    pageLoadScheduler.cleanupDistantImagesAroundCurrentPage()
  }

  func isAnimatedPage(for pageID: ReaderPageID) -> Bool {
    pageLoadScheduler.isAnimatedPage(for: pageID)
  }

  func shouldPrepareAnimatedPlayback(for pageID: ReaderPageID) -> Bool {
    pageLoadScheduler.shouldPrepareAnimatedPlayback(for: pageID)
  }

  func animatedSourceFileURL(for pageID: ReaderPageID) -> URL? {
    pageLoadScheduler.animatedSourceFileURL(for: pageID)
  }

  func prepareAnimatedPagePlaybackURL(pageID: ReaderPageID) async {
    await pageLoadScheduler.prepareAnimatedPagePlaybackURL(pageID: pageID)
  }

  func preloadImage(for pageID: ReaderPageID) async -> PlatformImage? {
    await pageLoadScheduler.preloadImage(for: pageID)
  }

  func clearPreloadedImages() {
    pageLoadScheduler.clearPreloadedImages()
  }

  func captureProgressSnapshot(for pageID: ReaderPageID?) -> ReaderPageProgressSnapshot? {
    guard let pageID, let readerPage = readerPage(for: pageID) else { return nil }
    return ReaderPageProgressSnapshot(
      bookId: readerPage.bookId,
      page: readerPage.pageNumber,
      completed: isBookCompleted(for: readerPage)
    )
  }

  func enqueueProgressChange(
    from previousSnapshot: ReaderPageProgressSnapshot?,
    to currentSnapshot: ReaderPageProgressSnapshot?
  ) {
    guard !incognitoMode else {
      logger.debug("⏭️ [Progress/Page] Skip enqueue: incognito mode enabled")
      return
    }

    // The first page observed for each book is the baseline the recording
    // threshold measures distance from.
    if let previousSnapshot, sessionStartPagesByBookId[previousSnapshot.bookId] == nil {
      sessionStartPagesByBookId[previousSnapshot.bookId] = previousSnapshot.page
    }
    if let currentSnapshot, sessionStartPagesByBookId[currentSnapshot.bookId] == nil {
      sessionStartPagesByBookId[currentSnapshot.bookId] = currentSnapshot.page
    }

    let precedingDispatch = progressDispatchTail
    progressDispatchTail = Task(priority: .userInitiated) {
      await precedingDispatch?.value
      await self.dispatchProgressChange(from: previousSnapshot, to: currentSnapshot)
    }
  }

  /// Checks `snapshot` against its book's recording gate, and keeps the book
  /// recording once it passes. A book's gate knows whether it was in progress
  /// when the session reached it.
  private func admitProgressRecording(_ snapshot: ReaderPageProgressSnapshot) -> Bool {
    let startPage = sessionStartPagesByBookId[snapshot.bookId] ?? snapshot.page
    var gate =
      progressRecordingGatesByBookId[snapshot.bookId]
      ?? ReaderProgressRecordingGate(
        wasInProgress: currentBook(forSegmentBookId: snapshot.bookId)?.isInProgress == true
      )
    guard
      gate.allowsRecording(
        distance: abs(snapshot.page - startPage),
        completed: snapshot.completed,
        pageCount: segmentPageRangeByBookId[snapshot.bookId]?.count
      )
    else {
      progressRecordingGatesByBookId[snapshot.bookId] = gate
      return false
    }
    gate.markRecorded()
    progressRecordingGatesByBookId[snapshot.bookId] = gate
    return true
  }

  private func dispatchProgressChange(
    from previousSnapshot: ReaderPageProgressSnapshot?,
    to currentSnapshot: ReaderPageProgressSnapshot?
  ) async {
    if let previousSnapshot,
      previousSnapshot.bookId != currentSnapshot?.bookId
    {
      if admitProgressRecording(previousSnapshot) {
        logger.debug(
          "🚿 [Progress/Page] Flush committed book boundary: book=\(previousSnapshot.bookId), page=\(previousSnapshot.page), completed=\(previousSnapshot.completed)"
        )
        await ReaderProgressDispatchService.shared.flushPageProgress(
          bookId: previousSnapshot.bookId,
          snapshotPage: previousSnapshot.page,
          snapshotCompleted: previousSnapshot.completed
        )
      } else {
        logger.debug(
          "⏭️ [Progress/Page] Skip boundary flush: below recording threshold, book=\(previousSnapshot.bookId), page=\(previousSnapshot.page)"
        )
      }
    }

    guard let currentSnapshot else { return }
    guard admitProgressRecording(currentSnapshot) else {
      logger.debug(
        "⏭️ [Progress/Page] Skip dispatch: below recording threshold, book=\(currentSnapshot.bookId), page=\(currentSnapshot.page)"
      )
      return
    }
    logger.debug(
      "📝 [Progress/Page] Dispatch committed snapshot: book=\(currentSnapshot.bookId), page=\(currentSnapshot.page), completed=\(currentSnapshot.completed)"
    )
    await ReaderProgressDispatchService.shared.submitPageProgress(
      bookId: currentSnapshot.bookId,
      page: currentSnapshot.page,
      completed: currentSnapshot.completed
    )
  }

  func flushProgress() {
    guard !incognitoMode else {
      logger.debug("⏭️ [Progress/Page] Skip flush: incognito mode enabled")
      return
    }

    let snapshot = captureProgressSnapshot(for: currentReaderPage?.id)

    logger.debug(
      "🚿 [Progress/Page] Flush requested from reader: book=\(snapshot?.bookId ?? "unknown"), hasCurrentPage=\(snapshot != nil)"
    )
    enqueueProgressChange(from: snapshot, to: nil)
  }

  private func isBookCompleted(for readerPage: ReaderPage) -> Bool {
    guard let range = segmentPageRangeByBookId[readerPage.bookId], !range.isEmpty else {
      return false
    }
    guard let currentPageIndex = pageIndex(for: readerPage.id) else { return false }
    return currentPageIndex >= range.upperBound - 1
  }

  func updateDualPageSettings(noCover: Bool) {
    let newIsolateCover = !noCover
    guard isolateCoverPageEnabled != newIsolateCover else { return }
    regenerateViewStatePreservingCurrentPosition {
      isolateCoverPageEnabled = newIsolateCover
    }
  }

  func updatePageLayout(_ layout: PageLayout) {
    let shouldForceDualPage = layout == .dual
    guard forceDualPagePairs != shouldForceDualPage else { return }
    regenerateViewStatePreservingCurrentPosition {
      forceDualPagePairs = shouldForceDualPage
    }
  }

  func updateSplitWidePageMode(_ mode: SplitWidePageMode) {
    guard splitWidePageMode != mode else { return }
    regenerateViewStatePreservingCurrentPosition {
      splitWidePageMode = mode
    }
  }

  func updatePageTransitionStyle(_ style: PageTransitionStyle) {
    guard pageTransitionStyle != style else { return }
    regenerateViewStatePreservingCurrentPosition {
      pageTransitionStyle = style
    }
  }

  func updateRotation(_ rotation: ReaderRotation) {
    guard self.rotation != rotation else { return }
    regenerateViewStatePreservingCurrentPosition {
      self.rotation = rotation
    }
    notifyPagePresentationInvalidation(.all)
  }

  func updateDualPagePresentationMode(_ isUsingDualPageMode: Bool) {
    guard isActuallyUsingDualPageMode != isUsingDualPageMode else { return }

    regenerateViewStatePreservingCurrentPosition {
      isActuallyUsingDualPageMode = isUsingDualPageMode
    }
  }

  func toggleIsolatePage(_ pageID: ReaderPageID) {
    guard let isolatePosition = isolatePosition(for: pageID) else { return }
    guard isPageEffectivelyPortrait(pageID) else { return }
    toggleIsolatePage(at: isolatePosition)
  }

  private func toggleIsolatePage(at isolatePosition: (bookId: String, localIndex: Int)) {

    var localIsolatePages = isolatePagesByBookId[isolatePosition.bookId] ?? []
    if localIsolatePages.contains(isolatePosition.localIndex) {
      localIsolatePages.remove(isolatePosition.localIndex)
    } else {
      localIsolatePages.insert(isolatePosition.localIndex)
    }
    isolatePagesByBookId[isolatePosition.bookId] = localIsolatePages
    rebuildIsolatePageIndices()
    regenerateViewState()

    let sortedLocalPages = localIsolatePages.sorted()
    Task {
      if let database = await DatabaseOperator.databaseIfConfigured() {
        await database.updateIsolatePages(
          bookId: isolatePosition.bookId,
          pages: sortedLocalPages
        )
      }
    }
  }

  private func regenerateViewState() {
    regenerateViewState(preserving: captureCurrentPositionAnchor())
  }

  private func regenerateViewState(preserving positionAnchor: ReaderPositionAnchor) {

    // Apply the split-wide preference consistently in single and dual presentations.
    let effectiveSplitWidePages = splitWidePageMode.isEnabled

    // Cover page isolation only applies when NOT in single page mode
    // In single page mode, every page is already isolated
    let shouldIsolateCover = isolateCoverPageEnabled && (forceDualPagePairs || isActuallyUsingDualPageMode)

    viewItems = generateViewItems(
      segments: segments,
      readerPages: readerPages,
      noCover: !shouldIsolateCover,
      allowDualPairs: isActuallyUsingDualPageMode,
      forceDualPairs: forceDualPagePairs,
      splitWidePages: effectiveSplitWidePages,
      keepsSplitSpreadsWhole: keepsSplitSpreadsWhole,
      pageCurl: pageTransitionStyle == .pageCurl,
      isolatePages: Set(isolatePages),
      rotation: rotation
    )
    viewItemIndexByPage = generateViewItemIndexMap(items: viewItems)
    restoreCurrentPosition(anchor: positionAnchor)
  }

  private func regenerateViewStatePreservingCurrentPosition(_ mutation: () -> Void) {
    let positionAnchor = captureCurrentPositionAnchor()
    let pendingNavigationTarget = navigationTarget
    mutation()
    regenerateViewState(preserving: positionAnchor)
    // Presentation restoration follows the committed position. Only explicit
    // navigation commands survive a rebuild, and only when they still resolve strictly.
    navigationTarget = pendingNavigationTarget.flatMap {
      matchingPositionAnchor(for: $0)
    }
  }

  func viewItem(at index: Int) -> ReaderViewItem? {
    guard index >= 0 && index < viewItems.count else { return nil }
    return viewItems[index]
  }

  func viewItem(for pageID: ReaderPageID) -> ReaderViewItem? {
    guard let index = viewItemIndexByPage[pageID] else { return nil }
    return viewItem(at: index)
  }

  func viewItemIndex(for item: ReaderViewItem) -> Int? {
    viewItems.firstIndex(of: item)
  }

  func requestNavigation(toPageID pageID: ReaderPageID?) {
    guard let pageID else {
      navigationTarget = nil
      return
    }
    guard let item = matchingViewItem(preferredPageID: pageID) else {
      navigationTarget = nil
      return
    }
    navigationTarget = ReaderPositionAnchor(
      item: item,
      focusedPageID: pageID,
      preferredSplitPart: preferredSplitPart(for: item, pageID: pageID)
    )
  }

  func requestNavigation(toViewItem viewItem: ReaderViewItem?) {
    requestNavigation(toViewItem: viewItem, splitPart: nil)
  }

  private func requestNavigation(
    toViewItem viewItem: ReaderViewItem?,
    splitPart explicitSplitPart: ReaderSplitPart?
  ) {
    guard
      let viewItem = matchingViewItem(
        preferredItem: viewItem,
        preferredPageID: viewItem?.pageID
      )
    else {
      navigationTarget = nil
      return
    }
    let currentFocusedPageID = resolvedCurrentPageID
    let focusedPageID: ReaderPageID
    if let currentFocusedPageID,
      viewItem.pageIDs.contains(currentFocusedPageID) || viewItem.pageID == currentFocusedPageID
    {
      focusedPageID = currentFocusedPageID
    } else {
      focusedPageID = viewItem.pageID
    }
    navigationTarget = ReaderPositionAnchor(
      item: viewItem,
      focusedPageID: focusedPageID,
      preferredSplitPart: explicitSplitPart ?? preferredSplitPart(for: viewItem, pageID: focusedPageID)
    )
  }

  /// Requests one paged step (tap, key, remote); false when there is nothing
  /// to step to. A whole spread has two stops, its start and end edges: a step
  /// first pans it to the edge the step leaves through, and stepping back onto
  /// a spread lands on its end edge. Steps chain from an in-flight target, so
  /// rapid steps still visit every stop.
  func requestPagedStep(offset: Int) -> Bool {
    guard offset != 0 else { return false }
    let isForward = offset > 0
    let base = navigationTarget ?? captureCurrentPositionAnchor()

    // A zoomed page only pans at its zoom, so while zoomed a step turns the
    // page, as it does for any other page.
    if !isZoomed, let item = base.item, isWholeSpread(item) {
      let restingEdges: Set<ReaderSpreadEdge>
      if navigationTarget != nil {
        restingEdges = [
          ReaderSpreadEdge(splitPart: base.preferredSplitPart)
            ?? wholeSpreadArrivalEdge(for: item, relativeTo: currentViewItem())
        ]
      } else {
        restingEdges = committedWholeSpreadRestingEdges(for: item.pageID)
      }
      let departureEdge: ReaderSpreadEdge = isForward ? .end : .start
      if !restingEdges.contains(departureEdge) {
        navigationTarget = ReaderPositionAnchor(
          item: item,
          focusedPageID: item.pageID,
          preferredSplitPart: departureEdge.splitPart
        )
        return true
      }
    }

    guard let item = adjacentViewItem(offset: offset) else { return false }
    let arrivalEdge: ReaderSpreadEdge = isForward ? .start : .end
    requestNavigation(
      toViewItem: item,
      splitPart: isWholeSpread(item) ? arrivalEdge.splitPart : nil
    )
    return true
  }

  func clearNavigationTarget() {
    navigationTarget = nil
  }

  func clearNavigationTarget(matching target: ReaderPositionAnchor) {
    guard navigationTarget == target else { return }
    navigationTarget = nil
  }

  func adjacentViewItem(from item: ReaderViewItem? = nil, offset: Int) -> ReaderViewItem? {
    guard offset != 0 else {
      return item ?? navigationTarget?.item ?? currentViewItem()
    }
    let anchorItem = item ?? navigationTarget?.item ?? currentViewItem()
    guard let anchorItem, let anchorIndex = viewItemIndex(for: anchorItem) else {
      return nil
    }
    return viewItem(at: anchorIndex + offset)
  }

  func updateCurrentPosition(pageID: ReaderPageID?) {
    guard let pageID else {
      currentPageID = nil
      currentViewItemID = nil
      splitPartPreference = nil
      syncPageLoadSchedulerCurrentPage()
      return
    }
    updateCurrentPosition(
      anchor: ReaderPositionAnchor(
        item: nil,
        focusedPageID: pageID,
        preferredSplitPart: splitPartPreference(forPageID: pageID)
      )
    )
  }

  private func resolvedCurrentPageID(
    for viewItem: ReaderViewItem?,
    preferredPageID: ReaderPageID?
  ) -> ReaderPageID? {
    guard let viewItem else { return preferredPageID }
    if let preferredPageID, viewItem.pageIDs.contains(preferredPageID) {
      return preferredPageID
    }
    return viewItem.pageID
  }

  func updateCurrentPosition(viewItem: ReaderViewItem?) {
    guard let viewItem else {
      currentViewItemID = nil
      currentPageID = nil
      splitPartPreference = nil
      syncPageLoadSchedulerCurrentPage()
      return
    }
    let focusedPageID = currentPageID ?? viewItem.pageID
    updateCurrentPosition(
      anchor: ReaderPositionAnchor(
        item: viewItem,
        focusedPageID: focusedPageID,
        preferredSplitPart: preferredSplitPart(for: viewItem, pageID: focusedPageID)
      )
    )
  }

  func captureCurrentPositionAnchor() -> ReaderPositionAnchor {
    let item = currentViewItem()
    let focusedPageID = resolvedCurrentPageID
    return ReaderPositionAnchor(
      item: item,
      focusedPageID: focusedPageID,
      preferredSplitPart: splitPartPreference(forPageID: focusedPageID ?? item?.pageID)
    )
  }

  func resolvedPositionAnchor(for anchor: ReaderPositionAnchor) -> ReaderPositionAnchor? {
    if let matchingAnchor = matchingPositionAnchor(for: anchor) {
      return matchingAnchor
    }
    guard let firstItem = viewItems.first else { return nil }
    return ReaderPositionAnchor(item: firstItem, focusedPageID: firstItem.pageID)
  }

  func matchingPositionAnchor(for anchor: ReaderPositionAnchor) -> ReaderPositionAnchor? {
    guard
      let resolvedItem = matchingViewItem(
        preferredItem: anchor.item,
        preferredPageID: anchor.focusedPageID,
        preferredSplitPart: anchor.preferredSplitPart
      )
    else {
      return nil
    }
    return ReaderPositionAnchor(
      item: resolvedItem,
      focusedPageID: resolvedCurrentPageID(
        for: resolvedItem,
        preferredPageID: anchor.focusedPageID
      ),
      preferredSplitPart: resolvedItem.preferredSplitPart(preserving: anchor)
    )
  }

  func updateCurrentPosition(anchor: ReaderPositionAnchor) {
    guard let resolvedAnchor = matchingPositionAnchor(for: anchor) else { return }
    assignCurrentPosition(resolvedAnchor)
  }

  private func restoreCurrentPosition(anchor: ReaderPositionAnchor) {
    guard let resolvedAnchor = resolvedPositionAnchor(for: anchor) else {
      currentViewItemID = nil
      currentPageID = nil
      splitPartPreference = nil
      syncPageLoadSchedulerCurrentPage()
      return
    }
    assignCurrentPosition(resolvedAnchor)
  }

  private func assignCurrentPosition(_ anchor: ReaderPositionAnchor) {
    currentViewItemID = anchor.item
    currentPageID = anchor.focusedPageID
    updateSplitPartPreference(for: anchor)
    syncPageLoadSchedulerCurrentPage()
  }

  private func updateSplitPartPreference(for anchor: ReaderPositionAnchor) {
    guard case .split(let id, let part) = anchor.item else {
      splitPartPreference = nil
      return
    }
    switch part {
    case .first, .second:
      splitPartPreference = (id, part)
    case .both:
      // A merged split keeps the previously committed side for the same page,
      // unless the anchor names one (a whole spread's committed edge).
      if let anchoredPart = anchor.preferredSplitPart, anchoredPart != .both {
        splitPartPreference = (id, anchoredPart)
      } else if splitPartPreference?.pageID != id {
        splitPartPreference = nil
      }
    }
  }

  /// Whether `item` is a whole spread: a split wide page kept whole in
  /// single-page presentation, panning across the viewport.
  func isWholeSpread(_ item: ReaderViewItem) -> Bool {
    guard keepsSplitSpreadsWhole, !isActuallyUsingDualPageMode else { return false }
    guard case .split(_, .both) = item else { return false }
    return true
  }

  /// Edge a whole spread opens at when a page host starts showing it. An
  /// explicit navigation target names its edge, and the current item reopens
  /// at its committed side. The item right before the current one is reached
  /// by stepping back, so it opens at its end edge; anything else opens at its
  /// start edge.
  func wholeSpreadArrivalEdge(
    for item: ReaderViewItem,
    relativeTo currentItem: ReaderViewItem?
  ) -> ReaderSpreadEdge {
    guard case .split(let pageID, .both) = item else { return .start }
    if let navigationTarget, navigationTarget.item == item,
      let edge = ReaderSpreadEdge(splitPart: navigationTarget.preferredSplitPart)
    {
      return edge
    }
    guard let currentItem, currentItem != item else {
      return ReaderSpreadEdge(splitPart: splitPartPreference(forPageID: pageID)) ?? .start
    }
    if let index = viewItemIndex(for: item),
      let currentIndex = viewItemIndex(for: currentItem),
      index == currentIndex - 1
    {
      return .end
    }
    return .start
  }

  /// Records the edges a whole spread's page host rests at after a pan
  /// settles or the host starts showing the committed item: none between its
  /// edges, both when it fits the viewport. Resting at one edge also makes it
  /// the committed split side, so rebuilds reopen the spread there.
  func recordWholeSpreadPosition(pageID: ReaderPageID, restingEdges: Set<ReaderSpreadEdge>) {
    wholeSpreadRestingEdges = (pageID, restingEdges)
    guard restingEdges.count == 1, let part = restingEdges.first?.splitPart else { return }
    guard splitPartPreference?.pageID != pageID || splitPartPreference?.part != part else { return }
    splitPartPreference = (pageID, part)
  }

  private func committedWholeSpreadRestingEdges(for pageID: ReaderPageID) -> Set<ReaderSpreadEdge> {
    if let wholeSpreadRestingEdges, wholeSpreadRestingEdges.pageID == pageID {
      return wholeSpreadRestingEdges.edges
    }
    return [ReaderSpreadEdge(splitPart: splitPartPreference(forPageID: pageID)) ?? .start]
  }

  /// Split Wide Pages set to Scroll keeps a split wide page whole in iOS
  /// single-page presentation, where the page hosts pan across it; every other
  /// mode pages through its halves, as macOS and tvOS always do.
  private var keepsSplitSpreadsWhole: Bool {
    #if os(iOS)
      splitWidePageMode == .scroll
    #else
      false
    #endif
  }

  func currentViewItem() -> ReaderViewItem? {
    resolvedViewItem(
      preferredItem: currentViewItemID,
      preferredPageID: currentPageID
    )
  }

  func isLeftSplitHalf(
    part: ReaderSplitPart,
    readingDirection: ReadingDirection,
    splitWidePageMode: SplitWidePageMode
  ) -> Bool {
    let isFirstHalf: Bool
    switch part {
    case .first:
      isFirstHalf = true
    case .second:
      isFirstHalf = false
    case .both:
      return true
    }
    let effectiveDirection = splitWidePageMode.effectiveReadingDirection(for: readingDirection)
    let shouldShowLeftFirst = effectiveDirection != .rtl
    return shouldShowLeftFirst ? isFirstHalf : !isFirstHalf
  }
}

private func generateViewItems(
  segments: [ReaderSegment],
  readerPages: [ReaderPage],
  noCover: Bool,
  allowDualPairs: Bool,
  forceDualPairs: Bool,
  splitWidePages: Bool,
  keepsSplitSpreadsWhole: Bool,
  pageCurl: Bool,
  isolatePages: Set<Int> = [],
  rotation: ReaderRotation = .none
) -> [ReaderViewItem] {
  guard !segments.isEmpty, !readerPages.isEmpty else { return [] }

  enum PageOrientation {
    case portrait
    case landscape
    case unknown

    var isKnownLandscape: Bool {
      self == .landscape
    }

    var isPairableInForcedDual: Bool {
      self != .landscape
    }
  }

  func effectiveOrientation(at index: Int) -> PageOrientation {
    let page = readerPages[index].page
    guard let width = page.width, let height = page.height else { return .unknown }
    let size = rotation.rotatedSize(
      CGSize(width: CGFloat(width), height: CGFloat(height))
    )
    return size.height > size.width ? .portrait : .landscape
  }

  var items: [ReaderViewItem] = []
  let shouldForceDualPairs = allowDualPairs && forceDualPairs

  var segmentStartIndex = 0
  for segment in segments {
    let segmentPageCount = segment.pages.count
    guard segmentPageCount > 0 else {
      continue
    }

    let segmentEndExclusive = segmentStartIndex + segmentPageCount
    var index = segmentStartIndex

    while index < segmentEndExclusive {
      if shouldForceDualPairs {
        let currentOrientation = effectiveOrientation(at: index)
        let isCoverPage = !noCover && index == segmentStartIndex
        let isWideCoverPage = isCoverPage && currentOrientation.isKnownLandscape
        let isWidePageEligibleForSplit =
          (splitWidePages || pageCurl)
          && currentOrientation.isKnownLandscape
          && (noCover || isWideCoverPage || index != segmentStartIndex)

        if isWidePageEligibleForSplit {
          items.append(.split(id: readerPages[index].id, part: .both))
          index += 1
          continue
        }

        if currentOrientation.isKnownLandscape && !pageCurl {
          items.append(.page(id: readerPages[index].id))
          index += 1
          continue
        }

        let nextIsPairable =
          index + 1 < segmentEndExclusive
          ? effectiveOrientation(at: index + 1).isPairableInForcedDual
          : true
        let shouldShowSingle =
          (isCoverPage && currentOrientation.isPairableInForcedDual) || index == segmentEndExclusive - 1
          || isolatePages.contains(index) || isolatePages.contains(index + 1)
          || !nextIsPairable  // next page is wide → keep it for its own item
        if shouldShowSingle {
          items.append(.page(id: readerPages[index].id))
          index += 1
        } else {
          let nextIndex = index + 1
          items.append(.dual(first: readerPages[index].id, second: readerPages[nextIndex].id))
          index += 2
        }
        continue
      }

      let currentOrientation = effectiveOrientation(at: index)
      let currentIsPortrait = currentOrientation == .portrait

      var useSinglePage = false
      var shouldSplitPage = false

      let isCoverPage = !noCover && index == segmentStartIndex
      let isWideCoverPage = isCoverPage && !currentIsPortrait

      // Wide pages split only when enabled. In dual-page mode that produces a two-slot
      // spread; in single-page presentation, one whole spread that pans, or two
      // half items where the platform pages through the halves.
      let isWidePageEligibleForSplit =
        (splitWidePages || (pageCurl && allowDualPairs))
        && !currentIsPortrait
        && (noCover || isWideCoverPage || index != segmentStartIndex)

      if isWidePageEligibleForSplit {
        shouldSplitPage = true
      }

      // Determine if page should be shown as single (without splitting)
      if !currentIsPortrait && !shouldSplitPage {
        useSinglePage = true
      }
      if isCoverPage && !isWideCoverPage {
        useSinglePage = true
      }
      if isolatePages.contains(index) {
        useSinglePage = true
      }
      if index == segmentEndExclusive - 1 {
        useSinglePage = true
      }

      if shouldSplitPage {
        if allowDualPairs || keepsSplitSpreadsWhole {
          items.append(.split(id: readerPages[index].id, part: .both))
        } else {
          items.append(.split(id: readerPages[index].id, part: .first))
          items.append(.split(id: readerPages[index].id, part: .second))
        }
        index += 1
      } else if useSinglePage {
        items.append(.page(id: readerPages[index].id))
        index += 1
      } else {
        let nextIsPortrait = effectiveOrientation(at: index + 1) == .portrait
        if allowDualPairs && index + 1 < segmentEndExclusive
          && nextIsPortrait
          && !isolatePages.contains(index + 1)
        {
          items.append(.dual(first: readerPages[index].id, second: readerPages[index + 1].id))
          index += 2
        } else {
          items.append(.page(id: readerPages[index].id))
          index += 1
        }
      }
    }

    items.append(
      .end(id: readerPages[segmentEndExclusive - 1].id)
    )
    segmentStartIndex = segmentEndExclusive
  }

  return items
}

private func generateViewItemIndexMap(items: [ReaderViewItem]) -> [ReaderPageID: Int] {
  var indices: [ReaderPageID: Int] = [:]
  for (index, item) in items.enumerated() {
    switch item {
    case .dual(let first, let second):
      if indices[first] == nil {
        indices[first] = index
      }
      if indices[second] == nil {
        indices[second] = index
      }
    default:
      let pageID = item.pageID
      if indices[pageID] == nil {
        indices[pageID] = index
      }
    }
  }
  return indices
}
