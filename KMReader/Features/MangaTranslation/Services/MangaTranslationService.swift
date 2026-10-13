import CoreGraphics
import Foundation

actor MangaTranslationService {
  static let shared = MangaTranslationService()

  private let provider: any MangaTranslationProvider
  private let logger = AppLogger(.reader)
  private var preparedSets: [String: (archive: ModelArchive, models: MangaModelSet)] = [:]
  private var modelPreparationArchive: ModelArchive?
  private var modelPreparationTask: Task<MangaModelPaths, Error>?
  private var modelPreparationGeneration = 0
  private var translationGeneration: UInt64 = 0
  private var translationGenerationByKey: [MangaTranslationPageKey: UInt64] = [:]

  init(provider: any MangaTranslationProvider = OpenAICompatibleTranslationProvider()) {
    self.provider = provider
  }

  func prepareModels(
    archive: ModelArchive,
    storage: ModelStorage? = nil,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
  ) async throws {
    _ = try await models(archive: archive, storage: storage, onProgress: onProgress)
  }

  func testProvider(
    configuration: MangaProviderConfig,
    preferences: MangaTranslationPreferences
  ) async throws -> [String] {
    let languages = MangaTranslationConfiguration.resolvedLanguages(metadata: nil, preferences: preferences)
    let testText = languages.sourceLanguage.hasPrefix("ja") ? "これはテストです。" : "This is a test."
    return try await provider.translate(
      segments: [MangaTextSegment(id: 0, text: testText)],
      sourceLanguage: languages.sourceLanguage,
      targetLanguage: languages.targetLanguage,
      metadata: nil,
      configuration: configuration
    )
  }

  private func models(
    archive: ModelArchive,
    storage: ModelStorage?,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
  ) async throws -> MangaModelSet {
    guard archive.isValid, archive.purpose == .mangaOCR else {
      throw MangaTranslationFailure.modelPreparation
    }
    if let prepared = preparedSets[archive.storageKey] { return prepared.models }
    if let modelPreparationTask, modelPreparationArchive == archive {
      return try await finishPreparation(
        modelPreparationTask,
        archive: archive,
        generation: modelPreparationGeneration
      )
    }

    modelPreparationTask?.cancel()
    modelPreparationGeneration += 1
    let generation = modelPreparationGeneration
    let resolvedStorage = try (storage ?? .shared).storage(for: archive)
    let task = Task<MangaModelPaths, Error> {
      try await MangaModelManager.preparePaths(
        archive: archive,
        storage: resolvedStorage,
        onProgress: onProgress
      )
    }
    modelPreparationArchive = archive
    modelPreparationTask = task
    return try await finishPreparation(task, archive: archive, generation: generation)
  }

  private func finishPreparation(
    _ task: Task<MangaModelPaths, Error>,
    archive: ModelArchive,
    generation: Int
  ) async throws -> MangaModelSet {
    do {
      let paths = try await task.value
      let models = try MangaModelManager.load(paths: paths)
      MangaModelLibrary.register(archive)
      if modelPreparationGeneration == generation {
        // Detector and recognizer may come from different archives; keep one
        // prepared set per selected archive and drop anything unselected.
        let keepKeys = Set(AppConfig.modelLibrary.selectedStorageKeys.values)
          .union([archive.storageKey])
        preparedSets = preparedSets.filter { keepKeys.contains($0.key) }
        preparedSets[archive.storageKey] = (archive, models)
        modelPreparationArchive = nil
        modelPreparationTask = nil
      }
      return models
    } catch {
      if modelPreparationGeneration == generation {
        modelPreparationArchive = nil
        modelPreparationTask = nil
      }
      throw error
    }
  }

  func translate(
    key: MangaTranslationPageKey,
    image: CGImage,
    configuration: MangaTranslationConfiguration,
    database: DatabaseOperator? = nil,
    storage: ModelStorage? = nil,
    forceProviderRetry: Bool = false,
    onProgress: @Sendable (MangaTranslationPhase) async -> Void = { _ in }
  ) async throws -> MangaPageTranslation {
    let generation = beginTranslation(for: key)
    defer { finishTranslation(for: key, generation: generation) }

    let cached = try? await MangaTranslationStore.fetch(key: key, database: database)
    if let cached {
      logger.info(
        "Manga cache hit: \(key.pageID.bookId)#\(key.pageID.pageNumber), regions=\(cached.regions.count), translated=\(cached.isTranslated)"
      )
    }
    if let cached, !forceProviderRetry {
      if cached.isTranslated, !cached.regions.isEmpty {
        try ensureTranslationCurrent(for: key, generation: generation)
        return cached
      }
      if cached.status == .recognitionOnly(.noText) {
        try ensureTranslationCurrent(for: key, generation: generation)
        return cached
      }
      if !configuration.canTranslate {
        try ensureTranslationCurrent(for: key, generation: generation)
        return cached
      }
    }
    if !configuration.canTranslate {
      throw configuration.isOffline ? MangaTranslationFailure.offline : MangaTranslationFailure.notConfigured
    }

    let regions: [MangaTextRegion]
    if let cached, !cached.regions.isEmpty {
      regions = cached.regions
    } else {
      let detectorModels = try await models(archive: configuration.detectorArchive, storage: storage)
      try ensureTranslationCurrent(for: key, generation: generation)
      let detector = try detectorModels.makeDetector()
      await onProgress(.detecting)
      let detectedRegions = try await runInference {
        try detector.detect(
          image: image,
          splitMode: key.splitMode,
          rotation: key.rotation,
          borderCropMode: key.borderCropMode
        )
      }
      try ensureTranslationCurrent(for: key, generation: generation)
      await onProgress(.recognizing)
      let recognizerModels = try await models(archive: configuration.recognizerArchive, storage: storage)
      let recognizer = try recognizerModels.makeRecognizer()
      regions = try await runInference {
        try recognizer.recognize(crops: detectedRegions, image: image, rotation: key.rotation)
      }
    }

    let status: MangaTranslationStatus
    if regions.isEmpty {
      status = .recognitionOnly(.noText)
    } else {
      do {
        try ensureTranslationCurrent(for: key, generation: generation)
        await onProgress(.translating)
        let translated: [String]
        if configuration.hasConfiguredProvider, let providerConfiguration = configuration.provider {
          translated = try await provider.translate(
            segments: regions.map { MangaTextSegment(id: $0.id, text: $0.text) },
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage,
            metadata: configuration.metadata,
            configuration: providerConfiguration
          )
        } else {
          translated = try await SystemTranslationProvider.translate(
            segments: regions.map { MangaTextSegment(id: $0.id, text: $0.text) },
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage
          )
        }
        let translatedByID = Dictionary(
          uniqueKeysWithValues: zip(regions, translated).map { ($0.0.id, $0.1) }
        )
        let translatedRegions = regions.map { region in
          MangaTextRegion(
            id: region.id,
            label: region.label,
            score: region.score,
            sourceBox: region.sourceBox,
            box: region.box,
            text: region.text,
            translatedText: translatedByID[region.id] ?? "",
            orientation: region.orientation
          )
        }
        try ensureTranslationCurrent(for: key, generation: generation)
        status = .translated
        let result = MangaPageTranslation(
          key: key,
          regions: translatedRegions,
          status: status,
          targetLanguage: configuration.targetLanguage,
          createdAt: Date()
        )
        try? await MangaTranslationStore.save(result, database: database)
        logger.info("Manga translation completed: \(translatedRegions.count) regions")
        return result
      } catch let error as MangaTranslationFailure {
        status = .recognitionOnly(error)
      } catch {
        status = .recognitionOnly(.network)
      }
    }

    let result = MangaPageTranslation(
      key: key,
      regions: regions,
      status: status,
      targetLanguage: configuration.targetLanguage,
      createdAt: Date()
    )
    try ensureTranslationCurrent(for: key, generation: generation)
    try? await MangaTranslationStore.save(result, database: database)
    logger.warning("Manga translation status: \(status), regions=\(regions.count)")
    return result
  }

  private func runInference<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
  ) async throws -> T {
    let task = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func beginTranslation(for key: MangaTranslationPageKey) -> UInt64 {
    translationGeneration &+= 1
    translationGenerationByKey[key] = translationGeneration
    return translationGeneration
  }

  private func ensureTranslationCurrent(
    for key: MangaTranslationPageKey,
    generation: UInt64
  ) throws {
    guard !Task.isCancelled, translationGenerationByKey[key] == generation else {
      throw CancellationError()
    }
  }

  private func finishTranslation(
    for key: MangaTranslationPageKey,
    generation: UInt64
  ) {
    if translationGenerationByKey[key] == generation {
      translationGenerationByKey.removeValue(forKey: key)
    }
  }

  func releaseModels() {
    preparedSets = [:]
    modelPreparationGeneration += 1
    modelPreparationTask?.cancel()
    modelPreparationTask = nil
    modelPreparationArchive = nil
  }

  func clearModels(
    storage: ModelStorage,
    archive: ModelArchive
  ) throws {
    releaseModels()
    try MangaModelManager.clear(storage: storage.storage(for: archive))
    MangaModelLibrary.remove(archive)
  }

  func clearTranslations(instanceId: String, database: DatabaseOperator) async throws {
    translationGenerationByKey = translationGenerationByKey.filter { $0.key.instanceId != instanceId }
    try await MangaTranslationStore.clear(instanceId: instanceId, database: database)
  }
}
