import CoreGraphics
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

extension ReaderViewModel {
  /// Translated pages take a lot of memory only as text regions, so the
  /// session cache can be generous; eviction is FIFO.
  private static let mangaTranslationResultCacheLimit = 80
  /// View items translated ahead of the current one while the queue is idle.
  private static let mangaTranslationPrefetchItemCount = 1

  var mangaTranslationResult: MangaPageTranslation? {
    guard let key = currentMangaTranslationSessionKey() else { return nil }
    return mangaTranslationResults[key]
  }

  var mangaTranslationLanguagesMatch: Bool {
    guard let bookId = resolvedCurrentPageID?.bookId else { return false }
    return mangaTranslationLanguagesMatch(forBookId: bookId)
  }

  func mangaTranslationLanguagesMatch(forBookId bookId: String) -> Bool {
    let languages = MangaTranslationConfiguration.resolvedLanguages(
      sourceLanguage: mangaTranslationMetadataByBookId[bookId]?.sourceLanguage,
      preferences: AppConfig.mangaTranslation
    )
    return MangaTranslationLanguage.isSameLanguage(
      source: languages.sourceLanguage,
      target: languages.targetLanguage
    )
  }

  /// Per-page state for the translate button pinned to a page image. A nil
  /// state hides the button. Only the focused page surfaces the live phase;
  /// other pages show their own result and whether they sit in the queue.
  func mangaTranslationButtonState(for pageID: ReaderPageID, splitMode: PageSplitMode)
    -> MangaTranslationButtonState?
  {
    guard mangaTranslationEnabled else { return nil }
    let result = mangaTranslationResult(for: pageID, splitMode: splitMode)
    let phase = resolvedCurrentPageID == pageID ? mangaTranslationPhase : nil
    let overlayVisible =
      result?.isTranslated == true && mangaTranslationOverlayVisible(for: pageID, splitMode: splitMode)
    let tint: MangaTranslationButtonState.Tint =
      phase?.isFailed == true ? .failure : (overlayVisible ? .active : .none)
    let isBusy = phase?.isBusy ?? mangaTranslationIsActive(for: pageID, splitMode: splitMode)
    let accessibilityLabel: String
    if result?.isTranslated == true {
      accessibilityLabel =
        overlayVisible
        ? String(localized: "Hide Translation")
        : String(localized: "Show Translation")
    } else {
      accessibilityLabel = phase?.title ?? String(localized: "manga.action.translatePage")
    }
    return MangaTranslationButtonState(
      icon: phase?.icon ?? AppIcon.mangaTranslation,
      isBusy: isBusy,
      tint: tint,
      isEnabled: !mangaTranslationLanguagesMatch(forBookId: pageID.bookId),
      accessibilityLabel: accessibilityLabel
    )
  }

  func mangaTranslationIsActive(for pageID: ReaderPageID, splitMode: PageSplitMode) -> Bool {
    pendingMangaTranslationQueueKeys().contains(sessionKey(for: pageID, splitMode: splitMode))
  }

  func handleMangaTranslationButtonTap(for pageID: ReaderPageID, splitMode: PageSplitMode) {
    if mangaTranslationResult(for: pageID, splitMode: splitMode)?.isTranslated == true {
      let key = sessionKey(for: pageID, splitMode: splitMode)
      mangaTranslationVisibilityOverrides[key] = !mangaTranslationOverlayVisible(
        for: pageID, splitMode: splitMode)
      notifyPagePresentationInvalidation(.pages([pageID]))
    } else {
      translatePage(pageID, splitMode: splitMode)
    }
  }

  /// A page's overlay shows unless it was individually hidden; the shared
  /// showMangaTranslation preference is the default for untouched pages.
  func mangaTranslationOverlayVisible(for pageID: ReaderPageID, splitMode: PageSplitMode) -> Bool {
    mangaTranslationVisibilityOverrides[sessionKey(for: pageID, splitMode: splitMode)]
      ?? showMangaTranslation
  }

  /// Translates one tapped page. A page in the current view item rides the
  /// usual item-wide queue so a dual-page spread still switches together; any
  /// other page (webtoon) gets a queue of its own.
  func translatePage(_ pageID: ReaderPageID, splitMode: PageSplitMode) {
    guard mangaTranslationEnabled, !mangaTranslationLanguagesMatch(forBookId: pageID.bookId) else { return }
    if let item = currentViewItem(), item.pageIDs.contains(pageID) {
      translateCurrentPage()
      return
    }
    let key = sessionKey(for: pageID, splitMode: splitMode)
    guard mangaTranslationInFlightKey != key else { return }
    startMangaTranslationQueue(
      keys: [key],
      frontForceRetry: mangaTranslationResults[key] != nil,
      frontManual: true
    )
  }

  func mangaTranslationResult(for data: NativePageData) -> MangaPageTranslation? {
    mangaTranslationResult(for: data.pageID, splitMode: data.splitMode)
  }

  func mangaTranslationResult(for pageID: ReaderPageID, splitMode: PageSplitMode) -> MangaPageTranslation? {
    mangaTranslationResults[sessionKey(for: pageID, splitMode: splitMode)]
  }

  func translateCurrentPage() {
    guard mangaTranslationEnabled, resolvedCurrentPageID != nil, !mangaTranslationLanguagesMatch else { return }
    guard !mangaTranslationPhase.isBusy else { return }
    startMangaTranslationQueue(
      keys: desiredQueueKeys(includeCachedFront: true),
      frontForceRetry: mangaTranslationResult != nil,
      frontManual: true
    )
  }

  func toggleMangaTranslation() {
    setMangaTranslationVisibility(!showMangaTranslation)
    // A global flip re-applies the shared default to every page holding a
    // result, dropping individual overrides.
    mangaTranslationVisibilityOverrides = [:]
    notifyPagePresentationInvalidation(.all)
  }

  private func setMangaTranslationVisibility(_ isVisible: Bool) {
    showMangaTranslation = isVisible
    guard AppConfig.mangaTranslation.showTranslation != isVisible else { return }
    var preferences = AppConfig.mangaTranslation
    preferences.showTranslation = isVisible
    AppConfig.mangaTranslation = preferences
  }

  func cancelMangaTranslation() {
    stopMangaTranslationQueue()
    mangaTranslationResults = [:]
    mangaTranslationResultOrder = []
    mangaTranslationVisibilityOverrides = [:]
    mangaTranslationPhase = .idle
  }

  /// Provider configuration edits are invisible to the session key's
  /// preference stamp, so the settings sheet's dismissal clears and re-runs
  /// the session cache wholesale.
  func refreshMangaTranslationConfiguration() {
    guard mangaTranslationEnabled else { return }
    cancelMangaTranslation()
    notifyPagePresentationInvalidation(.all)
    syncMangaTranslationPage()
  }

  private func stopMangaTranslationQueue() {
    mangaTranslationQueueID = nil
    mangaTranslationQueueTask?.cancel()
    mangaTranslationQueueTask = nil
    mangaTranslationQueueSnapshot = []
    mangaTranslationInFlightKey = nil
  }

  func setMangaTranslationEnabled(_ isEnabled: Bool) {
    guard mangaTranslationEnabled != isEnabled else { return }
    mangaTranslationEnabled = isEnabled
    if isEnabled {
      // Live Text and the translation overlay cannot analyze the same page.
      AppConfig.enableLiveText = false
      syncMangaTranslationPage()
      return
    }
    cancelMangaTranslation()
    notifyPagePresentationInvalidation(.all)
  }

  func syncMangaTranslationPage() {
    guard mangaTranslationEnabled, let frontKey = currentMangaTranslationSessionKey() else { return }
    let keys = desiredQueueKeys()
    if keys == pendingMangaTranslationQueueKeys(), mangaTranslationQueueTask != nil { return }
    if let cached = mangaTranslationResults[frontKey] {
      mangaTranslationPhase = phase(for: cached)
    }
    guard !keys.isEmpty else {
      stopMangaTranslationQueue()
      return
    }
    startMangaTranslationQueue(keys: keys, frontForceRetry: false, frontManual: false)
  }

  /// Current page first (unless already cached), then the rest of the visible
  /// item so a dual-page spread switches together, then the next few view
  /// items, skipping anything already translated this session.
  private func desiredQueueKeys(
    includeCachedFront: Bool = false
  ) -> [MangaTranslationSessionKey] {
    var keys: [MangaTranslationSessionKey] = []
    guard let frontKey = currentMangaTranslationSessionKey() else { return keys }
    if includeCachedFront || mangaTranslationResults[frontKey] == nil {
      keys.append(frontKey)
    }
    guard let currentItem = currentViewItem(),
      let startIndex = viewItemIndex(for: currentItem)
    else { return keys }
    for key in mangaTranslationSessionKeys(for: currentItem) {
      guard key != frontKey, mangaTranslationResults[key] == nil, !keys.contains(key) else { continue }
      keys.append(key)
    }
    var itemIndex = startIndex + 1
    var visitedItems = 0
    while itemIndex < viewItems.count, visitedItems < Self.mangaTranslationPrefetchItemCount {
      let item = viewItems[itemIndex]
      itemIndex += 1
      if item.isEnd { break }
      visitedItems += 1
      for key in mangaTranslationSessionKeys(for: item) {
        guard mangaTranslationResults[key] == nil, !keys.contains(key) else { continue }
        keys.append(key)
      }
    }
    return keys
  }

  /// Work the running queue still owes, including the item being processed.
  private func pendingMangaTranslationQueueKeys() -> [MangaTranslationSessionKey] {
    var keys = mangaTranslationQueueSnapshot
    if let inFlightKey = mangaTranslationInFlightKey {
      keys.insert(inFlightKey, at: 0)
    }
    return keys
  }

  private func startMangaTranslationQueue(
    keys: [MangaTranslationSessionKey],
    frontForceRetry: Bool,
    frontManual: Bool
  ) {
    if frontForceRetry, let front = keys.first {
      // A manual retry hides the previous overlay while it re-runs.
      mangaTranslationResults.removeValue(forKey: front)
      mangaTranslationResultOrder.removeAll { $0 == front }
      notifyPagePresentationInvalidation(.pages([front.pageID]))
    }
    stopMangaTranslationQueue()
    let queueID = UUID()
    mangaTranslationQueueID = queueID
    mangaTranslationQueueSnapshot = keys
    mangaTranslationQueueFrontForceRetry = frontForceRetry
    mangaTranslationQueueFrontManual = frontManual
    setMangaTranslationVisibility(true)
    if keys.first == currentMangaTranslationSessionKey() {
      mangaTranslationPhase = .preparingModels
    }
    mangaTranslationQueueTask = Task { [weak self] in
      await self?.runMangaTranslationQueue(queueID: queueID)
    }
  }

  private func runMangaTranslationQueue(queueID: UUID) async {
    while !mangaTranslationQueueSnapshot.isEmpty {
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      let sessionKey = mangaTranslationQueueSnapshot.removeFirst()
      // Only the page the user is looking at reports failures; the queue
      // front is pure prefetch whenever the current page is already cached.
      let isCurrentPageItem = sessionKey == currentMangaTranslationSessionKey()
      let forceProviderRetry = isCurrentPageItem && mangaTranslationQueueFrontForceRetry
      let isManual = isCurrentPageItem && mangaTranslationQueueFrontManual
      if mangaTranslationResults[sessionKey] != nil { continue }
      mangaTranslationInFlightKey = sessionKey
      await processMangaTranslationItem(
        sessionKey,
        queueID: queueID,
        forceProviderRetry: forceProviderRetry,
        reportsFailure: isCurrentPageItem,
        isManual: isManual
      )
      // A superseded queue must not clear the replacement's in-flight marker.
      if mangaTranslationInFlightKey == sessionKey {
        mangaTranslationInFlightKey = nil
      }
    }
    guard isCurrentMangaTranslationQueue(queueID) else { return }
    mangaTranslationQueueTask = nil
  }

  private func processMangaTranslationItem(
    _ sessionKey: MangaTranslationSessionKey,
    queueID: UUID,
    forceProviderRetry: Bool,
    reportsFailure: Bool,
    isManual: Bool
  ) async {
    let pageID = sessionKey.pageID
    do {
      let metadata = await mangaTranslationMetadata(for: pageID)
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      if mangaTranslationMetadataByBookId[pageID.bookId] != metadata {
        mangaTranslationMetadataByBookId[pageID.bookId] = metadata
      }
      let languages = MangaTranslationConfiguration.resolvedLanguages(
        metadata: metadata,
        preferences: AppConfig.mangaTranslation
      )
      guard
        !MangaTranslationLanguage.isSameLanguage(
          source: languages.sourceLanguage,
          target: languages.targetLanguage
        )
      else {
        if sessionKey == currentMangaTranslationSessionKey() {
          mangaTranslationPhase = .idle
        }
        return
      }
      let database = await DatabaseOperator.databaseIfConfigured()
      guard
        let configuration = try await MangaTranslationConfiguration.current(
          metadata: metadata,
          database: database
        )
      else {
        throw MangaTranslationFailure.modelPreparation
      }
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      let key = try await makeTranslationKey(
        for: pageID,
        sessionKey: sessionKey,
        configuration: configuration
      )
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      // The persisted cache answers before any image decode: finalized rows
      // need neither inference nor the provider.
      if !forceProviderRetry,
        let cached = try? await MangaTranslationStore.fetch(key: key, database: database),
        cached.isFinalized
      {
        guard isCurrentMangaTranslationQueue(queueID) else { return }
        storeMangaTranslationResult(cached, for: sessionKey)
        reportMangaTranslationFailure(
          cached.status.failure,
          reportsFailure: reportsFailure,
          isManual: isManual
        )
        return
      }
      guard configuration.canTranslate else {
        throw configuration.isOffline ? MangaTranslationFailure.offline : .notConfigured
      }
      guard let pageImage = await originalPageImage(for: pageID) else {
        throw MangaTranslationFailure.inference
      }
      #if os(iOS) || os(tvOS)
        let sourceImage = pageImage.cgImage
      #else
        let sourceImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
      #endif
      guard let sourceImage else { throw MangaTranslationFailure.inference }
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      let result = try await MangaTranslationService.shared.translate(
        key: key,
        image: sourceImage,
        configuration: configuration,
        database: database,
        forceProviderRetry: forceProviderRetry,
        onProgress: { [weak self] phase in
          guard let self else { return }
          await self.updateMangaTranslationPhase(phase, for: sessionKey, queueID: queueID)
        }
      )
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      if result.isFinalized {
        storeMangaTranslationResult(result, for: sessionKey)
        reportMangaTranslationFailure(
          result.status.failure,
          reportsFailure: reportsFailure,
          isManual: isManual
        )
      } else {
        let failure = result.status.failure ?? .inference
        failMangaTranslationItem(
          failure,
          for: sessionKey,
          reportsFailure: reportsFailure,
          isManual: isManual
        )
      }
    } catch let error as MangaTranslationFailure {
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      failMangaTranslationItem(
        error,
        for: sessionKey,
        reportsFailure: reportsFailure,
        isManual: isManual
      )
    } catch {
      guard isCurrentMangaTranslationQueue(queueID) else { return }
      failMangaTranslationItem(
        .inference,
        for: sessionKey,
        reportsFailure: reportsFailure,
        isManual: isManual
      )
    }
  }

  private func storeMangaTranslationResult(
    _ result: MangaPageTranslation,
    for sessionKey: MangaTranslationSessionKey
  ) {
    if mangaTranslationResults[sessionKey] == nil {
      mangaTranslationResultOrder.append(sessionKey)
    }
    mangaTranslationResults[sessionKey] = result
    // A fresh result always shows; an individual hide does not survive it.
    mangaTranslationVisibilityOverrides.removeValue(forKey: sessionKey)
    let overflow = mangaTranslationResultOrder.count - Self.mangaTranslationResultCacheLimit
    if overflow > 0 {
      for evictedKey in mangaTranslationResultOrder.prefix(overflow) {
        mangaTranslationResults.removeValue(forKey: evictedKey)
        mangaTranslationVisibilityOverrides.removeValue(forKey: evictedKey)
      }
      mangaTranslationResultOrder.removeFirst(overflow)
    }
    notifyPagePresentationInvalidation(.pages([sessionKey.pageID]))
    if sessionKey == currentMangaTranslationSessionKey() {
      mangaTranslationPhase = phase(for: result)
    }
  }

  private func failMangaTranslationItem(
    _ failure: MangaTranslationFailure,
    for sessionKey: MangaTranslationSessionKey,
    reportsFailure: Bool,
    isManual: Bool
  ) {
    if sessionKey == currentMangaTranslationSessionKey() {
      mangaTranslationPhase = failure == .noText ? .noText : .failed(failure)
    }
    reportMangaTranslationFailure(failure, reportsFailure: reportsFailure, isManual: isManual)
  }

  /// Prefetch failures stay silent; the current page reports configuration
  /// and network problems even on automatic attempts, and everything on a
  /// manual one.
  private func reportMangaTranslationFailure(
    _ failure: MangaTranslationFailure?,
    reportsFailure: Bool,
    isManual: Bool
  ) {
    guard let failure else { return }
    guard isManual || (reportsFailure && failure.notifiesDuringAutomaticTranslation) else { return }
    ErrorManager.shared.notify(message: failure.description)
  }

  private func phase(for result: MangaPageTranslation) -> MangaTranslationPhase {
    if result.isTranslated { return .completed }
    let failure = result.status.failure ?? .inference
    return failure == .noText ? .noText : .failed(failure)
  }

  private func currentMangaTranslationSessionKey() -> MangaTranslationSessionKey? {
    guard let pageID = resolvedCurrentPageID, let item = currentViewItem() else { return nil }
    let keys = mangaTranslationSessionKeys(for: item)
    return keys.first(where: { $0.pageID == pageID }) ?? keys.first
  }

  /// Keys for an item's pages as displayed, in reading order. A merged split
  /// renders as two half pages in dual-page presentation, so it takes one key
  /// per half — a whole-page key would never match the halves the pages look
  /// their results up with.
  private func mangaTranslationSessionKeys(for item: ReaderViewItem) -> [MangaTranslationSessionKey] {
    guard !item.isEnd else { return [] }
    if isActuallyUsingDualPageMode, case .split(let id, .both) = item {
      return [ReaderSplitPart.first, .second].map { part in
        sessionKey(for: id, splitMode: mangaSplitMode(for: part))
      }
    }
    return item.pageIDs.map { sessionKey(for: $0, splitMode: mangaSplitMode(for: item)) }
  }

  private func sessionKey(for pageID: ReaderPageID, splitMode: PageSplitMode) -> MangaTranslationSessionKey {
    MangaTranslationSessionKey(
      pageID: pageID,
      splitMode: splitMode,
      rotation: currentMangaRotation,
      borderCropMode: currentMangaBorderCropMode,
      configurationStamp: MangaTranslationSessionKey.currentConfigurationStamp()
    )
  }

  private func updateMangaTranslationPhase(
    _ phase: MangaTranslationPhase,
    for sessionKey: MangaTranslationSessionKey,
    queueID: UUID
  ) {
    guard isCurrentMangaTranslationQueue(queueID),
      sessionKey == currentMangaTranslationSessionKey()
    else { return }
    mangaTranslationPhase = phase
  }

  private func mangaSplitMode(for item: ReaderViewItem) -> PageSplitMode {
    guard case .split(_, let part) = item, part != .both else { return .none }
    return mangaSplitMode(for: part)
  }

  private func mangaSplitMode(for part: ReaderSplitPart) -> PageSplitMode {
    isLeftSplitHalf(
      part: part,
      readingDirection: readingDirection,
      splitWidePageMode: splitWidePageMode
    ) ? .leftHalf : .rightHalf
  }

  private var currentMangaRotation: ReaderRotation {
    readingDirection == .webtoon ? .none : rotation
  }

  private var currentMangaBorderCropMode: ReaderPageBorderCropMode {
    readingDirection == .webtoon ? .disabled : AppConfig.divinaPageBorderCropMode
  }

  private func makeTranslationKey(
    for pageID: ReaderPageID,
    sessionKey: MangaTranslationSessionKey,
    configuration: MangaTranslationConfiguration
  ) async throws -> MangaTranslationPageKey {
    let sourceURL = await getPageImageFileURL(pageID: pageID)
    let sourceSignature = try await sourceSignature(for: sourceURL)
    return MangaTranslationPageKey(
      instanceId: AppConfig.current.instanceId,
      pageID: pageID,
      splitMode: sessionKey.splitMode,
      rotation: sessionKey.rotation,
      borderCropMode: sessionKey.borderCropMode,
      sourceSignature: sourceSignature,
      providerSignature: configuration.providerSignature,
      modelSignature: configuration.modelSignature
    )
  }

  private func mangaTranslationMetadata(for pageID: ReaderPageID) async -> MangaTranslationMetadata? {
    guard let book = currentBook(forSegmentBookId: pageID.bookId) else { return nil }
    var series: Series?
    if let database = await DatabaseOperator.databaseIfConfigured() {
      series = try? await database.fetchSeriesDisplayItem(
        seriesId: book.seriesId,
        instanceId: AppConfig.current.instanceId
      )?.series
    }
    let authors =
      book.metadata.authors?.map(\.name)
      ?? series?.booksMetadata.authors?.map(\.name)
      ?? []
    let bookTitle = book.metadata.title.isEmpty ? book.name : book.metadata.title
    let seriesTitle = book.seriesTitle.isEmpty ? (series?.metadata.title ?? "") : book.seriesTitle
    return MangaTranslationMetadata(
      seriesTitle: seriesTitle,
      bookTitle: bookTitle,
      authors: authors,
      genres: series?.metadata.genres ?? [],
      sourceLanguage: series?.metadata.language
    )
  }

  private func sourceSignature(for sourceURL: URL?) async throws -> String {
    guard let sourceURL else { throw MangaTranslationFailure.inference }
    let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
    let modificationDate = attributes?[.modificationDate] as? Date
    let size = (attributes?[.size] as? Int64) ?? 0
    return MangaSignature.make([
      "url": sourceURL.path,
      "modifiedAt": String(modificationDate?.timeIntervalSince1970 ?? 0),
      "size": String(size),
    ])
  }

  private func isCurrentMangaTranslationQueue(_ queueID: UUID) -> Bool {
    mangaTranslationQueueID == queueID && !Task.isCancelled
  }
}
