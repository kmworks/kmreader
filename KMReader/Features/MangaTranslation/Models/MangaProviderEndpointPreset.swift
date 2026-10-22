import Foundation

enum MangaProviderEndpointPreset: String, CaseIterable, Identifiable {
  case openRouter
  case custom

  var id: Self { self }

  var title: String {
    switch self {
    case .openRouter:
      return "OpenRouter"
    case .custom:
      return String(localized: "Custom")
    }
  }

  var baseURL: String? {
    switch self {
    case .openRouter:
      return "https://openrouter.ai/api/v1"
    case .custom:
      return nil
    }
  }

  init(baseURL: String) {
    let normalizedURL = MangaProviderConfig.normalizedBaseURL(baseURL)
    self =
      Self.allCases.first { preset in
        guard let presetURL = preset.baseURL else { return false }
        return MangaProviderConfig.normalizedBaseURL(presetURL) == normalizedURL
      } ?? .custom
  }
}
