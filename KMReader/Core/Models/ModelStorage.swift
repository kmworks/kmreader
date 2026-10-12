import Foundation

nonisolated struct ModelStorage: Hashable, Sendable {
  let rootDirectory: URL

  var packagesDirectory: URL { rootDirectory.appendingPathComponent("Models") }
  var compiledDirectory: URL { rootDirectory.appendingPathComponent("CompiledModels") }
  var downloadsDirectory: URL { rootDirectory.appendingPathComponent("Downloads") }

  func storage(for archive: ModelArchive) -> ModelStorage {
    ModelStorage(
      rootDirectory:
        rootDirectory
        .appendingPathComponent("Bundles", isDirectory: true)
        .appendingPathComponent(archive.purpose.rawValue, isDirectory: true)
        .appendingPathComponent(archive.storageKey, isDirectory: true)
    )
  }

  nonisolated static var shared: ModelStorage {
    get throws {
      let rootDirectory = try AppStorageDirectory.supportDirectory()
        .appendingPathComponent("Models", isDirectory: true)
      try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var target = rootDirectory
      try? target.setResourceValues(values)
      return ModelStorage(rootDirectory: rootDirectory)
    }
  }
}
