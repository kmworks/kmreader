import Foundation

nonisolated enum MangaModelLibrary {
  static func selectedArchive(for role: MangaModelRole) -> ModelArchive? {
    let selectedStorageKeys = AppConfig.modelLibrary.selectedStorageKeys
    // Role keys landed after the single combined key; existing selections
    // keep working through the fallback until the next explicit select.
    let storageKey =
      selectedStorageKeys[role.selectionStorageKey]
      ?? selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] ?? ""
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

  static func select(_ archive: ModelArchive, for role: MangaModelRole) {
    guard archive.purpose == .mangaOCR else { return }
    var configuration = AppConfig.modelLibrary
    configuration.selectedStorageKeys[role.selectionStorageKey] = archive.storageKey
    // The legacy combined key keeps the other role working until both roles
    // have explicit picks.
    let roleKeys = MangaModelRole.allCases.map(\.selectionStorageKey)
    if roleKeys.allSatisfy({ configuration.selectedStorageKeys[$0] != nil }) {
      configuration.selectedStorageKeys.removeValue(forKey: ModelPurpose.mangaOCR.rawValue)
    }
    AppConfig.modelLibrary = configuration
  }

  static func select(_ archive: ModelArchive) {
    // Single-role packages must not claim the other role's key: leaving it on
    // its current value keeps the legacy fallback and any explicit pick alive.
    for role in MangaModelRole.allCases where MangaModelSet.supports(archive, for: role) {
      select(archive, for: role)
    }
  }

  static func remove(_ archive: ModelArchive) {
    var configuration = AppConfig.modelLibrary
    configuration.downloadedArchives.removeAll { $0.storageKey == archive.storageKey }
    let selectionKeys =
      [ModelPurpose.mangaOCR.rawValue] + MangaModelRole.allCases.map(\.selectionStorageKey)
    for key in selectionKeys where configuration.selectedStorageKeys[key] == archive.storageKey {
      configuration.selectedStorageKeys.removeValue(forKey: key)
    }
    AppConfig.modelLibrary = configuration
  }
}
