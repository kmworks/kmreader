import Foundation

nonisolated enum MangaTranslationFailure: String, Error, Codable, Sendable {
  case offline
  case notConfigured
  case modelPreparation
  case unsupportedModel
  case inference
  case noText
  case network
  case timeout
  case authentication
  case rateLimited
  case unavailable
  case languagePackRequired
  case unsupportedLanguagePair
  case invalidResponse

  var notifiesDuringAutomaticTranslation: Bool {
    switch self {
    case .inference, .noText:
      return false
    default:
      return true
    }
  }

  var description: String {
    switch self {
    case .offline:
      return String(localized: "manga.error.offline")
    case .notConfigured:
      return String(localized: "manga.error.notConfigured")
    case .modelPreparation:
      return String(localized: "manga.error.modelPreparation")
    case .unsupportedModel:
      return String(localized: "manga.error.unsupportedModel")
    case .inference:
      return String(localized: "manga.error.inference")
    case .noText:
      return String(localized: "manga.error.noText")
    case .network:
      return String(localized: "manga.error.network")
    case .timeout:
      return String(localized: "manga.error.timeout")
    case .authentication:
      return String(localized: "manga.error.authentication")
    case .rateLimited:
      return String(localized: "manga.error.rateLimited")
    case .unavailable:
      return String(localized: "manga.error.unavailable")
    case .languagePackRequired:
      #if os(macOS)
        return String(localized: "manga.error.languagePackRequired.macOS")
      #else
        return String(localized: "manga.error.languagePackRequired")
      #endif
    case .unsupportedLanguagePair:
      return String(localized: "manga.error.unsupportedLanguagePair")
    case .invalidResponse:
      return String(localized: "manga.error.invalidResponse")
    }
  }
}
