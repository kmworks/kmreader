import Foundation

nonisolated struct ModelPackageManifest: Codable, Hashable, Sendable {
  let formatVersion: Int
  let capabilities: [String]
  let minimumAppVersion: String?
  let components: [String: ModelPackageComponent]

  var isValid: Bool {
    formatVersion == 1 && !capabilities.isEmpty
      && Set(capabilities).count == capabilities.count
      && capabilities.allSatisfy(Self.isValidIdentifier)
      && (minimumAppVersion.map(Self.isValidVersion) ?? true)
      && !components.isEmpty
      && components.allSatisfy { Self.isValidIdentifier($0.key) && $0.value.isValid }
  }

  func matches(_ archive: ModelArchive) -> Bool {
    Set(capabilities) == Set(archive.capabilities)
      && minimumAppVersion == archive.minimumAppVersion
      && components == archive.components
  }

  static func isValidIdentifier(_ value: String) -> Bool {
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    return !value.isEmpty && value.count <= 64 && value != "." && value != ".."
      && value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
  }

  static func isValidRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains(".") && !components.contains("..") && !components.contains("")
  }

  static func isValidVersion(_ version: String) -> Bool {
    version.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
  }

  enum CodingKeys: String, CodingKey {
    case formatVersion = "format_version"
    case capabilities
    case minimumAppVersion = "minimum_app_version"
    case components
  }
}
