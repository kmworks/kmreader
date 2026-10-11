import Foundation

nonisolated enum MangaTranslationLanguage {
  static let defaultSource = "ja"

  static var systemTarget: String {
    let identifier = normalized(Locale.preferredLanguages.first ?? Locale.current.identifier) ?? "en"
    let components = identifier.split(separator: "-")
    guard let language = components.first else { return "en" }
    if components.count > 1, components[1].count == 4,
      components[1].allSatisfy({ $0.isLetter })
    {
      return "\(language)-\(components[1])"
    }
    return String(language)
  }

  static func normalized(_ language: String?) -> String? {
    guard let language else { return nil }
    let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")
    return value.isEmpty ? nil : value
  }

  static func pickerCodes(including language: String? = nil) -> [String] {
    var codes = Set(LanguageCodeHelper.commonLanguageCodes)
    codes.insert(systemTarget)
    if let language = normalized(language) {
      codes.insert(language)
    }
    return codes.sorted {
      LanguageCodeHelper.displayName(for: $0).localizedStandardCompare(
        LanguageCodeHelper.displayName(for: $1)
      ) == .orderedAscending
    }
  }

  static func promptName(for language: String) -> String {
    Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language
  }
}
