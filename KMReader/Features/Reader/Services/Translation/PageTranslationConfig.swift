import Foundation

nonisolated struct PageTranslationConfig: Sendable, Equatable {
  let isEnabled: Bool
  let targetLanguage: String
  let apiBaseURL: String
  let apiKey: String
  let model: String
  let reasoningEffort: String?

  var isUsable: Bool {
    isEnabled && !targetLanguage.isEmpty && !apiBaseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
  }
}
