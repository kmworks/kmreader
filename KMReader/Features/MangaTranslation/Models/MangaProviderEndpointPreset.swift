import Foundation

enum MangaProviderEndpointPreset: String, CaseIterable, Identifiable {
  case openAI
  case openRouter
  case deepSeek
  case custom

  var id: Self { self }

  var title: String {
    switch self {
    case .openAI:
      return "OpenAI"
    case .openRouter:
      return "OpenRouter"
    case .deepSeek:
      return "DeepSeek"
    case .custom:
      return String(localized: "Custom")
    }
  }

  var baseURL: String? {
    switch self {
    case .openAI:
      return "https://api.openai.com/v1"
    case .openRouter:
      return "https://openrouter.ai/api/v1"
    case .deepSeek:
      return "https://api.deepseek.com/v1"
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
