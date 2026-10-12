import Foundation

nonisolated enum MangaTranslationStatus: Hashable, Codable, Sendable {
  case translated
  case recognitionOnly(MangaTranslationFailure)

  var failure: MangaTranslationFailure? {
    if case .recognitionOnly(let failure) = self { return failure }
    return nil
  }
}
