import Foundation

nonisolated enum MangaModelLibrary {
  static var selectedArchive: ModelArchive? {
    let storageKey = AppConfig.modelLibrary.selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] ?? ""
    guard !storageKey.isEmpty else { return nil }
    return downloadedArchives().first { $0.storageKey == storageKey }
      ?? ModelCatalog.cached?.models(for: .mangaOCR).first { $0.storageKey == storageKey }
  }

  static func downloadedArchives() -> [ModelArchive] {
    AppConfig.modelLibrary.downloadedArchives
      .filter { $0.isValid && $0.purpose == .mangaOCR }
      .sorted {
        if $0.name == $1.name {
          return $0.version > $1.version
        }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
  }

  static func reconcile(storage: ModelStorage) {
    let registered = downloadedArchives()
    let known = Dictionary(
      (registered + (ModelCatalog.cached?.models(for: .mangaOCR) ?? [])).map { ($0.storageKey, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for archive in known.values {
      let status = MangaModelManager.status(storage: storage.storage(for: archive), archive: archive)
      if status.packageExists {
        register(archive)
      }
    }
    for archive in registered {
      let status = MangaModelManager.status(storage: storage.storage(for: archive), archive: archive)
      if !status.packageExists {
        remove(archive)
      }
    }
  }

  static func register(_ archive: ModelArchive) {
    guard archive.isValid, archive.purpose == .mangaOCR else { return }
    var configuration = AppConfig.modelLibrary
    configuration.downloadedArchives.removeAll { $0.storageKey == archive.storageKey }
    configuration.downloadedArchives.append(archive)
    AppConfig.modelLibrary = configuration
  }

  static func select(_ archive: ModelArchive) {
    guard archive.purpose == .mangaOCR else { return }
    var configuration = AppConfig.modelLibrary
    configuration.selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] = archive.storageKey
    AppConfig.modelLibrary = configuration
  }

  static func remove(_ archive: ModelArchive) {
    var configuration = AppConfig.modelLibrary
    configuration.downloadedArchives.removeAll { $0.storageKey == archive.storageKey }
    if configuration.selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] == archive.storageKey {
      configuration.selectedStorageKeys.removeValue(forKey: ModelPurpose.mangaOCR.rawValue)
    }
    AppConfig.modelLibrary = configuration
  }
}
