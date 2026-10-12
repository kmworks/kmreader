import Foundation

nonisolated struct MangaTranslationMetadata: Hashable, Sendable {
  let seriesTitle: String
  let bookTitle: String
  let authors: [String]
  let genres: [String]
  let sourceLanguage: String?

  var signature: String {
    MangaSignature.make([
      "seriesTitle": seriesTitle,
      "bookTitle": bookTitle,
      "authors": authors.joined(separator: "\u{1F}"),
      "genres": genres.joined(separator: "\u{1F}"),
    ])
  }

  var promptLines: [String] {
    var lines: [String] = []
    append("Series", value: seriesTitle, to: &lines)
    append("Chapter", value: bookTitle, to: &lines)
    append("Authors", value: authors.joined(separator: ", "), to: &lines)
    append("Genres", value: genres.joined(separator: ", "), to: &lines)
    return lines
  }

  private func append(_ label: String, value: String, to lines: inout [String]) {
    let cleaned =
      value
      .components(separatedBy: .newlines)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return }
    lines.append("\(label): \(String(cleaned.prefix(300)))")
  }
}
