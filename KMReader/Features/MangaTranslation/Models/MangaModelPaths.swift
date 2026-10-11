import Foundation

nonisolated struct MangaModelPaths: Sendable {
  let packagesDirectory: URL
  let compiledDirectory: URL
  let manifest: ModelPackageManifest

  func packageURL(component: String, file: String) -> URL? {
    guard let path = manifest.components[component]?.files[file] else { return nil }
    return packagesDirectory.appendingPathComponent(path)
  }

  func compiledModelURL(component: String, file: String) -> URL {
    compiledDirectory.appendingPathComponent("\(component)-\(file).mlmodelc")
  }
}
