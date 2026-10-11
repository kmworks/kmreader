import CoreML
import Foundation

nonisolated final class MangaModelSet {
  let manifest: ModelPackageManifest
  private let models: [String: MLModel]
  private let resources: [String: URL]

  init(manifest: ModelPackageManifest, models: [String: MLModel], resources: [String: URL]) {
    self.manifest = manifest
    self.models = models
    self.resources = resources
  }

  func model(component: String, file: String) throws -> MLModel {
    guard let model = models["\(component).\(file)"] else {
      throw MangaTranslationFailure.modelPreparation
    }
    return model
  }

  func resource(component: String, file: String) throws -> URL {
    guard let resource = resources["\(component).\(file)"] else {
      throw MangaTranslationFailure.modelPreparation
    }
    return resource
  }

  func labels(for component: String) -> [Int: ModelPackageLabel] {
    guard let labels = manifest.components[component]?.labels else { return [:] }
    return labels.reduce(into: [:]) { result, entry in
      guard let id = Int(entry.key) else { return }
      result[id] = entry.value
    }
  }

  func makeDetector() throws -> any MangaTextDetecting {
    guard let component = manifest.components["detector"],
      component.engine == .rtDetrV2 && component.engineVersion == 1
    else {
      throw MangaTranslationFailure.unsupportedModel
    }
    return RTDetrDetector(models: self)
  }

  func makeRecognizer() throws -> any MangaTextRecognizing {
    guard let component = manifest.components["recognizer"],
      component.engine == .mangaOCRTransformer && component.engineVersion == 1
    else {
      throw MangaTranslationFailure.unsupportedModel
    }
    return try MangaOCRRecognizer(models: self)
  }

  static func supports(_ archive: ModelArchive) -> Bool {
    guard archive.components["detector"] != nil, archive.components["recognizer"] != nil else {
      return false
    }
    return archive.components.allSatisfy { role, component in
      switch (role, component.engine, component.engineVersion) {
      case ("detector", .rtDetrV2, 1), ("recognizer", .mangaOCRTransformer, 1):
        true
      default:
        false
      }
    }
  }
}
