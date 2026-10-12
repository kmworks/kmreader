import Foundation

nonisolated struct ModelArchive: Hashable, Codable, Identifiable, Sendable {
  let id: String
  let name: String
  let version: Int
  let url: URL
  let sha256: String
  let bytes: Int?
  let license: String
  let purpose: ModelPurpose
  let capabilities: [String]
  let minimumAppVersion: String?
  let components: [String: ModelPackageComponent]
  let comment: String?

  init(
    id: String,
    name: String,
    version: Int,
    url: URL,
    sha256: String,
    bytes: Int?,
    license: String,
    purpose: ModelPurpose = .mangaOCR,
    capabilities: [String] = ["detection", "ocr"],
    minimumAppVersion: String? = nil,
    components: [String: ModelPackageComponent] = ModelPackageComponent.currentMangaOCRComponents,
    comment: String? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.url = url
    self.sha256 = sha256
    self.bytes = bytes
    self.license = license
    self.purpose = purpose
    self.capabilities = capabilities
    self.minimumAppVersion = minimumAppVersion
    self.components = components
    self.comment = comment
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    version = try container.decode(Int.self, forKey: .version)
    url = try container.decode(URL.self, forKey: .url)
    sha256 = try container.decode(String.self, forKey: .sha256)
    bytes = try container.decodeIfPresent(Int.self, forKey: .bytes)
    license = try container.decode(String.self, forKey: .license)
    let decodedPurpose = try container.decodeIfPresent(ModelPurpose.self, forKey: .purpose) ?? .mangaOCR
    purpose = decodedPurpose
    capabilities =
      try container.decodeIfPresent([String].self, forKey: .capabilities)
      ?? (decodedPurpose == .mangaOCR ? ["detection", "ocr"] : [])
    minimumAppVersion = try container.decodeIfPresent(String.self, forKey: .minimumAppVersion)
    components =
      try container.decodeIfPresent([String: ModelPackageComponent].self, forKey: .components)
      ?? (decodedPurpose == .mangaOCR ? ModelPackageComponent.currentMangaOCRComponents : [:])
    comment = try container.decodeIfPresent(String.self, forKey: .comment)
  }

  var storageKey: String { "\(id)-\(sha256.prefix(12))" }

  var isValid: Bool {
    let allowedIDCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let manifest = ModelPackageManifest(
      formatVersion: 1,
      capabilities: capabilities,
      minimumAppVersion: minimumAppVersion,
      components: components
    )
    return !id.isEmpty && id.count <= 128 && id != "." && id != ".."
      && id.rangeOfCharacter(from: allowedIDCharacters.inverted) == nil
      && !name.isEmpty && version > 0 && purpose.isValid && manifest.isValid
      && (url.scheme == "https" || url.isFileURL)
      && sha256.count == 64 && sha256.allSatisfy(\.isHexDigit)
      && (bytes ?? 1) > 0
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case version
    case url
    case sha256
    case bytes
    case license
    case purpose
    case capabilities
    case minimumAppVersion = "minimum_app_version"
    case components
    case comment
  }
}
