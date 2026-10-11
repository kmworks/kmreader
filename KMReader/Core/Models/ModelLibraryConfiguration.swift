import Foundation

nonisolated struct ModelLibraryConfiguration: Codable, Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  static let defaultCatalogURL = "https://models.kmworks.date/v1/catalog.json"

  var catalogURL: String
  var catalog: ModelCatalog?
  var downloadedArchives: [ModelArchive]
  var selectedStorageKeys: [String: String]

  init(
    catalogURL: String = ModelLibraryConfiguration.defaultCatalogURL,
    catalog: ModelCatalog? = nil,
    downloadedArchives: [ModelArchive] = [],
    selectedStorageKeys: [String: String] = [:]
  ) {
    self.catalogURL = catalogURL
    self.catalog = catalog
    self.downloadedArchives = downloadedArchives
    self.selectedStorageKeys = selectedStorageKeys
  }

  init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8),
      let decoded = RawCodableStore.decode(Self.self, from: data)
    else {
      return nil
    }
    self = decoded
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      catalogURL: try container.decodeIfPresent(String.self, forKey: .catalogURL)
        ?? ModelLibraryConfiguration.defaultCatalogURL,
      catalog: try container.decodeIfPresent(ModelCatalog.self, forKey: .catalog),
      downloadedArchives: try container.decodeIfPresent([ModelArchive].self, forKey: .downloadedArchives) ?? [],
      selectedStorageKeys: try container.decodeIfPresent([String: String].self, forKey: .selectedStorageKeys) ?? [:]
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(catalogURL, forKey: .catalogURL)
    try container.encode(catalog, forKey: .catalog)
    try container.encode(downloadedArchives, forKey: .downloadedArchives)
    try container.encode(selectedStorageKeys, forKey: .selectedStorageKeys)
  }

  nonisolated var rawValue: String {
    guard let data = RawCodableStore.encode(self), let value = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return value
  }

  private enum CodingKeys: String, CodingKey {
    case catalogURL
    case catalog
    case downloadedArchives
    case selectedStorageKeys
  }
}
