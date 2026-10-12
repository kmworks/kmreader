import Foundation

nonisolated enum ModelCatalogError: String, Error, Sendable {
  case invalidResponse

  var description: String {
    String(localized: "model.error.invalidResponse")
  }
}

extension ModelCatalogError: LocalizedError {
  var errorDescription: String? { description }
}
