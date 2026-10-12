import Foundation

nonisolated struct MangaTranslationEnvelope: Decodable {
  let translations: [MangaTextSegment]
}
