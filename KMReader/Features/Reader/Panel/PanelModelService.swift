import Foundation

actor PanelModelService {
  static let shared = PanelModelService()
  private let logger = AppLogger(.reader)

  private var preparationTasks: [String: Task<PanelModelLocation, Error>] = [:]

  func installedModel() async -> PanelModelLocation? {
    guard let storage = try? ModelStorage.shared else { return nil }
    PanelModelLibrary.reconcile(storage: storage)
    return PanelModelLibrary.installedArchive().flatMap { location(for: $0, storage: storage) }
  }

  func prepare(
    archive: ModelArchive,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
  ) async throws -> PanelModelLocation {
    guard PanelModelLibrary.isSupported(archive) else {
      throw MangaTranslationFailure.unsupportedModel
    }
    if let task = preparationTasks[archive.storageKey] {
      return try await task.value
    }
    let storage = try ModelStorage.shared.storage(for: archive)
    let task = Task<PanelModelLocation, Error> {
      let paths = try await MangaModelManager.prepareSupportedPaths(
        archive: archive, storage: storage, onProgress: onProgress)
      let location = PanelModelLocation(
        url: paths.compiledModelURL(component: "detector", file: "model"),
        version: "\(archive.version)-\(archive.sha256.prefix(12))"
      )
      guard await RFDETRCoreMLDetector.prepare(location) else {
        throw MangaTranslationFailure.modelPreparation
      }
      PanelModelLibrary.register(archive)
      return location
    }
    preparationTasks[archive.storageKey] = task
    defer { preparationTasks.removeValue(forKey: archive.storageKey) }
    do {
      return try await task.value
    } catch {
      logger.error("[PanelModel] preparation failed: \(error)")
      throw error
    }
  }

  func prepareLatest(
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
  ) async throws -> PanelModelLocation {
    let catalog = try await ModelCatalogService.fetch()
    guard let archive = PanelModelLibrary.catalogArchive(in: catalog) else {
      throw MangaTranslationFailure.unsupportedModel
    }
    if let installed = await installedModel(), installed.version == "\(archive.version)-\(archive.sha256.prefix(12))" {
      return installed
    }
    return try await prepare(archive: archive, onProgress: onProgress)
  }

  func location(for archive: ModelArchive, storage: ModelStorage) -> PanelModelLocation? {
    guard PanelModelLibrary.isSupported(archive) else { return nil }
    let paths = storage.storage(for: archive)
    let status = MangaModelManager.status(storage: paths, archive: archive)
    guard status.packageExists, status.compiledExists else { return nil }
    return PanelModelLocation(
      url: paths.compiledDirectory.appendingPathComponent("detector-model.mlmodelc"),
      version: "\(archive.version)-\(archive.sha256.prefix(12))"
    )
  }

  func clear(archive: ModelArchive) async throws {
    preparationTasks[archive.storageKey]?.cancel()
    preparationTasks.removeValue(forKey: archive.storageKey)
    try MangaModelManager.clear(storage: ModelStorage.shared.storage(for: archive))
    PanelModelLibrary.remove(archive)
  }
}
