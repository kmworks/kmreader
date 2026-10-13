import CoreML
import CryptoKit
import Foundation

nonisolated struct MangaModelManager {
  static func prepare(
    archive: ModelArchive,
    storage: ModelStorage,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
  ) async throws -> MangaModelSet {
    let paths = try await preparePaths(archive: archive, storage: storage, onProgress: onProgress)
    return try load(paths: paths)
  }

  static func preparePaths(
    archive: ModelArchive,
    storage: ModelStorage,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
  ) async throws -> MangaModelPaths {
    try validateSupport(archive: archive)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: storage.rootDirectory, withIntermediateDirectories: true)

    let installedManifest: ModelPackageManifest?
    do {
      installedManifest = try validatePackage(at: storage.packagesDirectory, archive: archive)
    } catch {
      if fileManager.fileExists(atPath: storage.packagesDirectory.path) {
        try fileManager.removeItem(at: storage.packagesDirectory)
      }
      if fileManager.fileExists(atPath: storage.compiledDirectory.path) {
        try fileManager.removeItem(at: storage.compiledDirectory)
      }
      installedManifest = nil
    }

    if installedManifest == nil {
      let downloadedArchive = try await download(archive: archive, storage: storage, onProgress: onProgress)
      let temporaryPackage = storage.rootDirectory.appendingPathComponent("Models.next")
      if fileManager.fileExists(atPath: temporaryPackage.path) {
        try fileManager.removeItem(at: temporaryPackage)
      }
      do {
        try MangaTARArchive.extract(downloadedArchive, to: temporaryPackage)
        _ = try validatePackage(at: temporaryPackage, archive: archive)
        if fileManager.fileExists(atPath: storage.packagesDirectory.path) {
          try fileManager.removeItem(at: storage.packagesDirectory)
        }
        try fileManager.moveItem(at: temporaryPackage, to: storage.packagesDirectory)
      } catch {
        if fileManager.fileExists(atPath: temporaryPackage.path) {
          try? fileManager.removeItem(at: temporaryPackage)
        }
        throw error
      }
    }

    guard let manifest = try validatePackage(at: storage.packagesDirectory, archive: archive) else {
      throw MangaTranslationFailure.modelPreparation
    }
    try fileManager.createDirectory(at: storage.compiledDirectory, withIntermediateDirectories: true)
    for (componentName, component) in manifest.components {
      for fileName in component.coreMLFileNames {
        guard let relativePath = component.files[fileName] else {
          throw MangaTranslationFailure.modelPreparation
        }
        let packageURL = storage.packagesDirectory.appendingPathComponent(relativePath)
        let compiledURL = storage.compiledDirectory.appendingPathComponent("\(componentName)-\(fileName).mlmodelc")
        if !fileManager.fileExists(atPath: compiledURL.path) {
          let temporaryURL = try await MLModel.compileModel(at: packageURL)
          if fileManager.fileExists(atPath: compiledURL.path) {
            try fileManager.removeItem(at: compiledURL)
          }
          try fileManager.moveItem(at: temporaryURL, to: compiledURL)
        }
      }
    }
    return MangaModelPaths(
      packagesDirectory: storage.packagesDirectory,
      compiledDirectory: storage.compiledDirectory,
      manifest: manifest
    )
  }

  static func validateSupport(archive: ModelArchive) throws {
    guard archive.isValid, archive.purpose == .mangaOCR else {
      throw MangaTranslationFailure.modelPreparation
    }
    guard MangaModelSet.supports(archive) else {
      throw MangaTranslationFailure.unsupportedModel
    }
  }

  nonisolated static func load(paths: MangaModelPaths) throws -> MangaModelSet {
    var models: [String: MLModel] = [:]
    var resources: [String: URL] = [:]
    for (componentName, component) in paths.manifest.components {
      let configuration = MLModelConfiguration()
      #if targetEnvironment(simulator)
        // Simulator GPU inference can corrupt detection and OCR outputs.
        configuration.computeUnits = .cpuOnly
      #else
        // GPU/ANE specialize the decoder graph per sequence bucket and each
        // specialization adds gigabytes of compile state, which kills
        // memory-constrained devices on long decodes; the CPU runs the small
        // recognizer at the same speed with flat memory.
        configuration.computeUnits = componentName == "detector" ? .cpuAndGPU : .cpuOnly
      #endif
      for (fileName, relativePath) in component.files {
        let key = "\(componentName).\(fileName)"
        if relativePath.hasSuffix(".mlpackage") {
          let compiledURL = paths.compiledModelURL(component: componentName, file: fileName)
          do {
            models[key] = try MLModel(contentsOf: compiledURL, configuration: configuration)
          } catch let error as NSError {
            if error.domain == MLModelErrorDomain && error.code == MLModelError.io.rawValue {
              try? FileManager.default.removeItem(at: compiledURL)
            }
            throw error
          }
        } else {
          guard let resourceURL = paths.packageURL(component: componentName, file: fileName) else {
            throw MangaTranslationFailure.modelPreparation
          }
          resources[key] = resourceURL
        }
      }
    }
    return MangaModelSet(manifest: paths.manifest, models: models, resources: resources)
  }

  nonisolated static func status(storage: ModelStorage, archive: ModelArchive) -> MangaModelStorageStatus {
    let manifest = try? validatePackage(at: storage.packagesDirectory, archive: archive)
    let compiledExists =
      manifest?.components.allSatisfy { componentName, component in
        component.coreMLFileNames.allSatisfy { fileName in
          FileManager.default.fileExists(
            atPath: storage.compiledDirectory.appendingPathComponent("\(componentName)-\(fileName).mlmodelc").path
          )
        }
      } ?? false
    return MangaModelStorageStatus(
      packageExists: manifest != nil,
      compiledExists: compiledExists,
      packageBytes: directoryBytes(storage.packagesDirectory),
      compiledBytes: directoryBytes(storage.compiledDirectory),
      downloadBytes: directoryBytes(storage.downloadsDirectory)
    )
  }

  nonisolated static func clear(storage: ModelStorage) throws {
    for directory in [storage.packagesDirectory, storage.compiledDirectory, storage.downloadsDirectory] {
      if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
      }
    }
  }

  private static func download(
    archive: ModelArchive,
    storage: ModelStorage,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void
  ) async throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: storage.downloadsDirectory, withIntermediateDirectories: true)
    let destination = storage.downloadsDirectory.appendingPathComponent("models.tar")
    let partial = storage.downloadsDirectory.appendingPathComponent("models.tar.part")
    if fileManager.fileExists(atPath: partial.path) {
      try fileManager.removeItem(at: partial)
    }
    defer { try? fileManager.removeItem(at: partial) }

    if archive.url.isFileURL {
      try fileManager.copyItem(at: archive.url, to: partial)
    } else {
      var request = URLRequest(url: archive.url)
      request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
      let delegate = MangaModelDownloadDelegate(
        destination: partial,
        expectedBytes: archive.bytes.map(Int64.init),
        onProgress: onProgress
      )
      let response = try await delegate.download(with: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw MangaTranslationFailure.modelPreparation
      }
    }

    let attributes = try fileManager.attributesOfItem(atPath: partial.path)
    let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard byteCount > 0 else { throw MangaTranslationFailure.modelPreparation }
    if let expectedBytes = archive.bytes, Int64(expectedBytes) != byteCount {
      throw MangaTranslationFailure.modelPreparation
    }
    let input = try FileHandle(forReadingFrom: partial)
    defer { try? input.close() }
    var hash = SHA256()
    while true {
      let chunk = input.readData(ofLength: 1024 * 1024)
      if chunk.isEmpty { break }
      hash.update(data: chunk)
    }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest == archive.sha256.lowercased() else {
      throw MangaTranslationFailure.modelPreparation
    }
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: partial, to: destination)
    return destination
  }

  nonisolated private static func validatePackage(
    at directory: URL,
    archive: ModelArchive
  ) throws -> ModelPackageManifest? {
    let manifestURL = directory.appendingPathComponent("manifest.json")
    guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
    let data = try Data(contentsOf: manifestURL)
    guard data.count <= 1024 * 1024,
      let manifest = try? JSONDecoder().decode(ModelPackageManifest.self, from: data),
      manifest.isValid, manifest.matches(archive)
    else {
      throw MangaTranslationFailure.modelPreparation
    }
    try validateSupport(archive: archive)
    for component in manifest.components.values {
      for relativePath in component.files.values {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(relativePath).path) else {
          throw MangaTranslationFailure.modelPreparation
        }
      }
    }
    return manifest
  }

  nonisolated private static func directoryBytes(_ directory: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return 0 }
    var total: Int64 = 0
    for case let file as String in enumerator {
      let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file).path)
      total += (attributes?[.size] as? Int64) ?? 0
    }
    return total
  }
}
