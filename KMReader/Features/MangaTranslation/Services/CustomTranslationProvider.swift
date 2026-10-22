import Foundation

struct CustomTranslationProvider: MangaTranslationProvider {
  private let logger = AppLogger(.reader)

  func translate(
    segments: [MangaTextSegment],
    sourceLanguage: String,
    targetLanguage: String,
    metadata: MangaTranslationMetadata?,
    configuration: MangaProviderConfig
  ) async throws -> [String] {
    guard !segments.isEmpty else { return [] }
    guard configuration.isConfigured, let url = configuration.endpoint("chat/completions") else {
      throw MangaTranslationFailure.notConfigured
    }

    let payload: [String: Any] = [
      "source_language": sourceLanguage,
      "target_language": targetLanguage,
      "segments": segments.map { ["id": $0.id, "text": $0.text] },
    ]
    let payloadText = try jsonString(payload)
    let body = try JSONSerialization.data(
      withJSONObject: [
        "model": configuration.model,
        "messages": [
          [
            "role": "system",
            "content": MangaTranslationPrompt.systemPrompt(
              sourceLanguage: sourceLanguage,
              targetLanguage: targetLanguage,
              metadata: metadata
            ),
          ],
          ["role": "user", "content": payloadText],
        ],
      ],
      options: [.sortedKeys]
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = MangaProviderRequest.timeoutInterval
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = body

    logger.info("Manga provider request: \(segments.count) segments")
    let (data, httpResponse) = try await MangaProviderRequest.data(for: request)
    logger.info("Manga provider response: HTTP \(httpResponse.statusCode)")
    guard data.count <= 4 * 1024 * 1024 else {
      throw MangaTranslationFailure.invalidResponse
    }

    do {
      let envelope = try JSONDecoder().decode(MangaChatCompletionEnvelope.self, from: data)
      guard let content = envelope.choices.first?.message.content,
        let contentData = content.data(using: .utf8)
      else {
        throw MangaTranslationFailure.invalidResponse
      }
      let translations = try JSONDecoder().decode(MangaTranslationEnvelope.self, from: contentData).translations
      let expectedIDs = Set(segments.map(\.id))
      let actualIDs = translations.map(\.id)
      guard actualIDs.count == Set(actualIDs).count,
        Set(actualIDs) == expectedIDs,
        translations.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
      else {
        throw MangaTranslationFailure.invalidResponse
      }
      let byID = Dictionary(uniqueKeysWithValues: translations.map { ($0.id, $0.text) })
      return segments.map { byID[$0.id] ?? "" }
    } catch let error as MangaTranslationFailure {
      throw error
    } catch {
      throw MangaTranslationFailure.invalidResponse
    }
  }

  private func jsonString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else {
      throw MangaTranslationFailure.invalidResponse
    }
    return text
  }
}
