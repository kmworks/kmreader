import Foundation

struct MangaProviderModelService {
  static func fetchModels(
    configuration: MangaProviderConfig
  ) async throws -> [String] {
    let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = configuration.endpoint("models"), !apiKey.isEmpty else {
      throw MangaTranslationFailure.notConfigured
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = MangaProviderRequest.timeoutInterval
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await MangaProviderRequest.data(for: request)
    guard data.count <= 1024 * 1024,
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let items = dictionary["data"] as? [[String: Any]]
    else {
      throw MangaTranslationFailure.invalidResponse
    }
    let models = items.compactMap { $0["id"] as? String }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return Array(Set(models)).sorted()
  }
}
