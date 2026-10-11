import Foundation

struct ModelCatalogService {
  static func fetch() async throws -> ModelCatalog {
    guard let url = URL(string: AppConfig.modelLibrary.catalogURL), url.scheme == "https" else {
      throw ModelCatalogError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
      data.count <= 1024 * 1024
    else {
      throw ModelCatalogError.invalidResponse
    }
    let catalog = try JSONDecoder().decode(ModelCatalog.self, from: data)
    guard catalog.isValid, catalog.models.allSatisfy({ $0.url.scheme == "https" }) else {
      throw ModelCatalogError.invalidResponse
    }
    var configuration = AppConfig.modelLibrary
    configuration.catalog = catalog
    AppConfig.modelLibrary = configuration
    return catalog
  }
}
