//
// LanguageCodeHelper.swift
//
//

import Foundation

nonisolated struct LanguageCodeHelper {
  static let commonLanguageCodes: [String] = [
    "en", "zh", "ja", "ko", "fr", "de", "es", "it", "pt", "ru",
    "ar", "th", "vi", "hi", "tr", "pl", "nl", "sv", "da", "fi",
    "no", "cs", "hu", "ro", "el", "he", "id", "ms", "uk", "bg",
    "hr", "sk", "sl", "et", "lv", "lt", "mt", "ga", "cy", "is",
  ]

  static func displayName(for languageCode: String) -> String {
    if languageCode.isEmpty {
      return "None"
    }

    let identifier = languageCode.replacingOccurrences(of: "_", with: "-")
    if let displayName = Locale.current.localizedString(forIdentifier: identifier) {
      return displayName.capitalized
    }
    return identifier.uppercased()
  }

  static func allLanguageCodes() -> [String] {
    var codes = Set<String>()

    codes.formUnion(commonLanguageCodes)

    for identifier in Locale.availableIdentifiers {
      if let code = identifier.components(separatedBy: "-").first,
        code.count == 2
      {
        codes.insert(code)
      }
    }

    return Array(codes).sorted()
  }
}
