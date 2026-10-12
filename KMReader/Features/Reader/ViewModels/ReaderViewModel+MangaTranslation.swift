import CoreGraphics
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

extension ReaderViewModel {
  func translateCurrentPage(showsFailureNotification: Bool = true) {
    guard AppConfig.mangaTranslation.isEnabled, let pageID = resolvedCurrentPageID else { return }
    guard !mangaTranslationPhase.isBusy else { return }

    let forceProviderRetry = mangaTranslationResult != nil
    let taskID = UUID()
    mangaTranslationTask?.cancel()
    mangaTranslationTaskID = taskID
    mangaTranslationResult = nil
    setMangaTranslationVisibility(true)
    mangaTranslationPhase = .preparingModels
    mangaTranslationKey = makeTranslationKey(for: pageID)
    notifyPagePresentationInvalidation(.pages([pageID]))
    mangaTranslationTask = Task { [weak self] in
      guard let self else { return }
      do {
        let metadata = await mangaTranslationMetadata(for: pageID)
        guard isCurrentMangaTranslationTask(taskID) else { return }
        let database = await DatabaseOperator.databaseIfConfigured()
        guard
          let configuration = try await MangaTranslationConfiguration.current(
            metadata: metadata,
            database: database
          )
        else {
          throw MangaTranslationFailure.modelPreparation
        }
        guard isCurrentMangaTranslationTask(taskID) else { return }
        let key = try await makeTranslationKey(for: pageID, configuration: configuration)
        guard isCurrentMangaTranslationTask(taskID) else { return }
        mangaTranslationKey = key
        guard let pageImage = await originalPageImage(for: pageID) else {
          throw MangaTranslationFailure.inference
        }
        #if os(iOS) || os(tvOS)
          let sourceImage = pageImage.cgImage
        #else
          let sourceImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let sourceImage else { throw MangaTranslationFailure.inference }
        guard isCurrentMangaTranslationTask(taskID) else { return }
        let result = try await MangaTranslationService.shared.translate(
          key: key,
          image: sourceImage,
          configuration: configuration,
          database: database,
          forceProviderRetry: forceProviderRetry,
          onProgress: { [weak self] phase in
            guard let self else { return }
            await self.updateMangaTranslationPhase(phase, taskID: taskID)
          }
        )
        guard isCurrentMangaTranslationTask(taskID) else { return }
        mangaTranslationResult = result
        if result.isTranslated {
          mangaTranslationPhase = .completed
        } else {
          let failure = result.status.failure ?? .inference
          mangaTranslationPhase = failure == .noText ? .noText : .failed(failure)
          reportMangaTranslationFailure(failure, showsNotification: showsFailureNotification)
        }
        mangaTranslationTask = nil
        mangaTranslationTaskID = nil
        notifyPagePresentationInvalidation(.pages([pageID]))
      } catch let error as MangaTranslationFailure {
        guard isCurrentMangaTranslationTask(taskID) else { return }
        mangaTranslationResult = nil
        mangaTranslationPhase = .failed(error)
        mangaTranslationTask = nil
        mangaTranslationTaskID = nil
        reportMangaTranslationFailure(error, showsNotification: showsFailureNotification)
        notifyPagePresentationInvalidation(.pages([pageID]))
      } catch {
        guard isCurrentMangaTranslationTask(taskID) else { return }
        mangaTranslationResult = nil
        mangaTranslationPhase = .failed(.inference)
        mangaTranslationTask = nil
        mangaTranslationTaskID = nil
        reportMangaTranslationFailure(.inference, showsNotification: showsFailureNotification)
        notifyPagePresentationInvalidation(.pages([pageID]))
      }
    }
  }

  private func reportMangaTranslationFailure(
    _ failure: MangaTranslationFailure,
    showsNotification: Bool
  ) {
    guard showsNotification || failure.notifiesDuringAutomaticTranslation else { return }
    ErrorManager.shared.notify(message: failure.description)
  }

  func toggleMangaTranslation() {
    setMangaTranslationVisibility(!showMangaTranslation)
    guard let pageID = mangaTranslationResult?.key.pageID else { return }
    notifyPagePresentationInvalidation(.pages([pageID]))
  }

  private func setMangaTranslationVisibility(_ isVisible: Bool) {
    showMangaTranslation = isVisible
    guard AppConfig.mangaTranslation.showTranslation != isVisible else { return }
    var preferences = AppConfig.mangaTranslation
    preferences.showTranslation = isVisible
    AppConfig.mangaTranslation = preferences
  }

  func mangaTranslationResult(for data: NativePageData) -> MangaPageTranslation? {
    mangaTranslationResult(for: data.pageID, splitMode: data.splitMode)
  }

  func mangaTranslationResult(for pageID: ReaderPageID, splitMode: PageSplitMode) -> MangaPageTranslation? {
    guard let result = mangaTranslationResult else { return nil }
    guard result.key.pageID == pageID,
      result.key.splitMode == splitMode,
      result.key.rotation == currentMangaRotation,
      result.key.borderCropMode == currentMangaBorderCropMode
    else { return nil }
    return result
  }

  private var currentMangaSplitMode: PageSplitMode {
    guard case .split(_, let part)? = currentViewItem(), part != .both else { return .none }
    return isLeftSplitHalf(
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
    configuration: MangaTranslationConfiguration
  ) async throws -> MangaTranslationPageKey {
    let sourceURL = await getPageImageFileURL(pageID: pageID)
    let sourceSignature = try await sourceSignature(for: sourceURL)
    return MangaTranslationPageKey(
      instanceId: AppConfig.current.instanceId,
      pageID: pageID,
      splitMode: currentMangaSplitMode,
      rotation: currentMangaRotation,
      borderCropMode: currentMangaBorderCropMode,
      sourceSignature: sourceSignature,
      providerSignature: configuration.providerSignature,
      modelSignature: configuration.modelSignature
    )
  }

  private func makeTranslationKey(for pageID: ReaderPageID) -> MangaTranslationPageKey {
    MangaTranslationPageKey(
      instanceId: AppConfig.current.instanceId,
      pageID: pageID,
      splitMode: currentMangaSplitMode,
      rotation: currentMangaRotation,
      borderCropMode: currentMangaBorderCropMode,
      sourceSignature: "pending",
      providerSignature: "pending",
      modelSignature: "pending"
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

  private func isCurrentMangaTranslationTask(_ taskID: UUID) -> Bool {
    mangaTranslationTaskID == taskID && !Task.isCancelled
  }

  private func updateMangaTranslationPhase(
    _ phase: MangaTranslationPhase,
    taskID: UUID
  ) {
    guard isCurrentMangaTranslationTask(taskID) else { return }
    mangaTranslationPhase = phase
  }

  func cancelMangaTranslation() {
    mangaTranslationTaskID = nil
    mangaTranslationTask?.cancel()
    mangaTranslationTask = nil
    mangaTranslationKey = nil
    mangaTranslationResult = nil
    mangaTranslationPhase = .idle
  }

  func setMangaTranslationEnabled(_ isEnabled: Bool) {
    if isEnabled {
      syncMangaTranslationPage()
      return
    }
    cancelMangaTranslation()
    notifyPagePresentationInvalidation(.all)
  }

  func syncMangaTranslationPage() {
    guard AppConfig.mangaTranslation.isEnabled, let pageID = resolvedCurrentPageID else { return }
    let key = makeTranslationKey(for: pageID)
    if let currentKey = mangaTranslationKey,
      currentKey.pageID == key.pageID,
      currentKey.splitMode == key.splitMode,
      currentKey.rotation == key.rotation,
      currentKey.borderCropMode == key.borderCropMode
    {
      return
    }
    mangaTranslationTaskID = nil
    mangaTranslationTask?.cancel()
    mangaTranslationTask = nil
    mangaTranslationKey = key
    mangaTranslationResult = nil
    mangaTranslationPhase = .idle
    translateCurrentPage(showsFailureNotification: false)
  }
}
