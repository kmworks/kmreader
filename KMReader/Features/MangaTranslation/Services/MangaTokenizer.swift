import Foundation

nonisolated struct MangaTokenizer {
  private static let firstRegularTokenID = 5

  private let tokens: [String]

  init(url: URL) throws {
    tokens = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
  }

  func decode(_ ids: [Int]) -> String {
    ids.compactMap { id in
      guard id >= Self.firstRegularTokenID, tokens.indices.contains(id) else { return nil }
      let token = tokens[id]
      return token.hasPrefix("##") ? String(token.dropFirst(2)) : token
    }.joined()
  }
}
