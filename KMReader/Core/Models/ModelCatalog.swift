import Foundation

nonisolated struct ModelCatalog: Codable, Equatable, Sendable {
  let formatVersion: Int
  let models: [ModelArchive]

  var isValid: Bool {
    let ids = models.map(\.id)
    return formatVersion == 2 && !models.isEmpty && Set(ids).count == ids.count
      && models.allSatisfy(\.isValid)
  }

  func models(for purpose: ModelPurpose) -> [ModelArchive] {
    models.filter { $0.purpose == purpose }
  }

  func archive(id: String, purpose: ModelPurpose? = nil) -> ModelArchive? {
    models.first { $0.id == id && (purpose == nil || $0.purpose == purpose) }
  }

  nonisolated static var cached: ModelCatalog? {
    guard let catalog = AppConfig.modelLibrary.catalog, catalog.isValid else { return nil }
    return catalog
  }

  enum CodingKeys: String, CodingKey {
    case formatVersion = "format_version"
    case models
  }
}
