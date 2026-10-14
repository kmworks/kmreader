import Foundation

nonisolated struct ModelPurpose: RawRepresentable, Hashable, Codable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var isValid: Bool {
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    return !rawValue.isEmpty && rawValue.count <= 64 && rawValue != "." && rawValue != ".."
      && rawValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil
  }

  static let mangaOCR = ModelPurpose(rawValue: "manga_ocr")
}
