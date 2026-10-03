import Foundation

nonisolated struct PageTranslationLLMService: Sendable {
  enum TranslationError: Error {
    case invalidURL
    case httpError(Int)
    case invalidResponse
    case contentMismatch
  }

  private let config: PageTranslationConfig
  private let session: URLSession
  private let logger = AppLogger(.reader)

  init(config: PageTranslationConfig) {
    self.config = config
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 60
    self.session = URLSession(configuration: configuration)
  }

  func translate(_ bubbleTexts: [String]) async throws -> [String] {
    let request = try makeRequest(bubbleTexts)

    var lastError: Error?
    for attempt in 0...1 {
      do {
        let startedAt = Date()
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
          guard (200..<300).contains(httpResponse.statusCode) else {
            // 4xx is a caller/configuration problem; retrying cannot fix it.
            throw TranslationError.httpError(httpResponse.statusCode)
          }
        }
        let translations = try parseTranslations(from: data, expectedCount: bubbleTexts.count)
        try validateLengthRatio(translations: translations, sources: bubbleTexts)
        logger.debug(
          "✅ [Translate] \(bubbleTexts.count) bubbles in \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s"
        )
        for (source, translated) in zip(bubbleTexts, translations) {
          logger.debug(
            "  [Translate] \"\(source.replacingOccurrences(of: "\n", with: " "))\" -> \"\(translated.replacingOccurrences(of: "\n", with: " "))\""
          )
        }
        return translations
      } catch let error as TranslationError {
        throw error
      } catch {
        lastError = error
        if attempt == 0 {
          logger.warning("⚠️ [Translate] LLM request failed, retrying once: \(error)")
        }
      }
    }
    throw lastError ?? TranslationError.invalidResponse
  }

  private func makeRequest(_ bubbleTexts: [String]) throws -> URLRequest {
    let baseURL = config.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: baseURL + "/chat/completions") else {
      throw TranslationError.invalidURL
    }

    let systemPrompt = """
      You are a manga dialogue translator. Translate the Japanese, Korean, or English manga \
      dialogue in the user's JSON array into natural, colloquial \(config.targetLanguage). \
      Keep the same number of entries and the same order. Output only a JSON array of strings, \
      no commentary.
      """

    let userContent = String(decoding: try JSONSerialization.data(withJSONObject: bubbleTexts), as: UTF8.self)
    var body: [String: Any] = [
      "model": config.model,
      "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": userContent],
      ],
    ]
    // No temperature: some providers reject values outside their own default.
    if let reasoningEffort = config.reasoningEffort {
      body["reasoning_effort"] = reasoningEffort
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  // A wildly off total-length ratio (truncation or runaway generation) means the
  // model lost track of the array shape; treating it as unusable protects the page.
  private func validateLengthRatio(translations: [String], sources: [String]) throws {
    let sourceCount = sources.reduce(0) { $0 + $1.count }
    let translatedCount = translations.reduce(0) { $0 + $1.count }
    guard sourceCount > 0 else { throw TranslationError.contentMismatch }
    let ratio = Double(translatedCount) / Double(sourceCount)
    guard (0.2...4.0).contains(ratio) else { throw TranslationError.contentMismatch }
  }

  private func parseTranslations(from data: Data, expectedCount: Int) throws -> [String] {
    guard
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = json["choices"] as? [[String: Any]],
      let message = choices.first?["message"] as? [String: Any],
      let content = message["content"] as? String
    else { throw TranslationError.invalidResponse }

    var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
      text = text.replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
      text = text.replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
      text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard
      let arrayData = text.data(using: .utf8),
      let translations = try JSONSerialization.jsonObject(with: arrayData) as? [String],
      translations.count == expectedCount
    else { throw TranslationError.contentMismatch }
    return translations
  }
}
