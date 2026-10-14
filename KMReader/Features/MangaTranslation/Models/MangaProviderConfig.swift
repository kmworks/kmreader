import Foundation
import GRDB

nonisolated struct MangaProviderConfig: Hashable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
  static let databaseTableName = "manga_translation_providers"

  let id: String
  var baseURL: String
  var model: String
  var displayName: String
  var apiKey: String

  init(
    id: String = UUID().uuidString,
    baseURL: String,
    model: String,
    displayName: String,
    apiKey: String = ""
  ) {
    self.id = id
    self.baseURL = baseURL
    self.model = model
    self.displayName = displayName
    self.apiKey = apiKey
  }

  init(row: Row) throws {
    id = row["id"]
    baseURL = row["base_url"]
    model = row["model"]
    displayName = row["display_name"]
    apiKey = row["api_key"]
  }

  var isConfigured: Bool {
    endpoint("chat/completions") != nil
      && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var resolvedDisplayName: String {
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    if let host = URLComponents(string: baseURL)?.host, !host.isEmpty {
      return host
    }
    return baseURL
  }

  func endpoint(_ path: String) -> URL? {
    guard var components = URLComponents(string: Self.normalizedBaseURL(baseURL)),
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      components.host?.isEmpty == false
    else {
      return nil
    }
    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + (basePath.isEmpty ? "" : basePath + "/") + suffix
    components.query = nil
    components.fragment = nil
    return components.url
  }

  func signature(
    sourceLanguage: String,
    targetLanguage: String,
    metadata: MangaTranslationMetadata?
  ) -> String {
    MangaSignature.make([
      "baseURL": Self.normalizedBaseURL(baseURL),
      "model": model,
      "sourceLanguage": sourceLanguage,
      "targetLanguage": targetLanguage,
      "metadata": metadata?.signature ?? "",
      "promptVersion": "2",
    ])
  }

  func encode(to container: inout PersistenceContainer) throws {
    container[Column("id")] = id
    container[Column("base_url")] = baseURL
    container[Column("model")] = model
    container[Column("display_name")] = displayName
    container[Column("api_key")] = apiKey
  }

  static func normalizedBaseURL(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while result.count > 1 && result.hasSuffix("/") {
      result.removeLast()
    }
    return result
  }

  enum CodingKeys: String, CodingKey {
    case id
    case baseURL = "base_url"
    case model
    case displayName = "display_name"
    case apiKey = "api_key"
  }
}
