import Foundation

nonisolated struct ModelPackageManifest: Codable, Hashable, Sendable {
  let formatVersion: Int
  let capabilities: [String]
  let components: [String: ModelPackageComponent]

  var isValid: Bool {
    formatVersion == 1 && !capabilities.isEmpty
      && Set(capabilities).count == capabilities.count
      && capabilities.allSatisfy(Self.isValidIdentifier)
      && !components.isEmpty
      && components.allSatisfy { Self.isValidIdentifier($0.key) && $0.value.isValid }
  }

  func matches(_ archive: ModelArchive) -> Bool {
    Set(capabilities) == Set(archive.capabilities)
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

  enum CodingKeys: String, CodingKey {
    case formatVersion = "format_version"
    case capabilities
    case components
  }
}
