import Foundation

nonisolated enum PanelModelLibrary {
  static let modelID = "manga-panel-rfdetr-2026"

  static var installedVersion: String? {
    get { AppConfig.installedPanelModelVersion }
    set { AppConfig.installedPanelModelVersion = newValue }
  }

  static func downloadedArchives() -> [ModelArchive] {
    AppConfig.modelLibrary.downloadedArchives
      .filter { isSupported($0) }
      .sorted { $0.version > $1.version }
  }

  static func installedArchive() -> ModelArchive? {
    downloadedArchives().first { archive in
      guard let storage = try? ModelStorage.shared else { return false }
      let status = MangaModelManager.status(storage: storage.storage(for: archive), archive: archive)
      return status.packageExists && status.compiledExists
    }
  }

  static func reconcile(storage: ModelStorage) {
    for archive in downloadedArchives() {
      let status = MangaModelManager.status(storage: storage.storage(for: archive), archive: archive)
      if !status.packageExists || !status.compiledExists {
        installedVersion = nil
        remove(archive)
      }
    }
  }

  static func register(_ archive: ModelArchive) {
    guard isSupported(archive) else { return }
    var configuration = AppConfig.modelLibrary
    configuration.downloadedArchives.removeAll { $0.id == archive.id && $0.purpose == archive.purpose }
    configuration.downloadedArchives.append(archive)
    AppConfig.modelLibrary = configuration
    installedVersion = "\(archive.version)-\(archive.sha256.prefix(12))"
  }

  static func remove(_ archive: ModelArchive) {
    var configuration = AppConfig.modelLibrary
    configuration.downloadedArchives.removeAll { $0.storageKey == archive.storageKey }
    AppConfig.modelLibrary = configuration
    installedVersion = nil
  }

  static func catalogArchive(in catalog: ModelCatalog) -> ModelArchive? {
    catalog.models(for: .panelDetection).filter { isSupported($0) }.max { $0.version < $1.version }
  }

  static func isSupported(_ archive: ModelArchive) -> Bool {
    guard archive.isValid, archive.purpose == .panelDetection,
      archive.capabilities == ["detection"], archive.components.count == 1,
      let detector = archive.components["detector"]
    else { return false }
    return detector.engine == .rfDetr && detector.engineVersion == 1
      && detector.files == ["model": "detector.mlpackage"]
  }
}
