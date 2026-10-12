import Foundation

#if os(iOS) || os(macOS)
  import Translation
#endif

nonisolated enum SystemTranslationProvider {
  static var displayName: String {
    String(localized: "System Translation")
  }

  static var isAvailable: Bool {
    #if os(iOS) || os(macOS)
      if #available(iOS 26.0, macOS 26.0, *) {
        return true
      }
    #endif
    return false
  }

  static func translate(
    segments: [MangaTextSegment],
    sourceLanguage: String,
    targetLanguage: String
  ) async throws -> [String] {
    guard !segments.isEmpty else { return [] }
    #if os(iOS) || os(macOS)
      if #available(iOS 26.0, macOS 26.0, *) {
        do {
          let session = TranslationSession(
            installedSource: Locale.Language(identifier: sourceLanguage),
            target: Locale.Language(identifier: targetLanguage)
          )
          let requests = segments.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id))
          }
          let responses = try await session.translations(from: requests)
          var translationsByID: [String: String] = [:]
          for response in responses {
            if let identifier = response.clientIdentifier {
              translationsByID[identifier] = response.targetText
            }
          }
          let translations = segments.map { translationsByID[String($0.id)] ?? "" }
          guard responses.count == segments.count,
            translations.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
          else {
            throw MangaTranslationFailure.invalidResponse
          }
          return translations
        } catch is CancellationError {
          throw CancellationError()
        } catch let error as MangaTranslationFailure {
          throw error
        } catch {
          AppLogger(.reader).error("System translation failed: \(error)")
          throw MangaTranslationFailure.unavailable
        }
      }
    #endif
    throw MangaTranslationFailure.unavailable
  }
}
