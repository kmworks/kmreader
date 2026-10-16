//
// ReadiumCSSLoader.swift
//
//

import Foundation

struct ReadiumCSSLoader {
  private static let filePrefix = "KMReadiumCSS"
  private static let baseSubdirectory = "ReadiumCSS"
  private static var cache: [String: (before: String, defaultCSS: String, after: String)] = [:]

  static func cssAssets(
    language: String?,
    readingProgression: WebPubReadingProgression?
  ) -> (before: String, defaultCSS: String, after: String) {
    let variant = resolveVariantSubdirectory(
      language: language,
      readingProgression: readingProgression
    )
    let cacheKey = variant ?? "default"
    if let cached = cache[cacheKey] {
      return cached
    }

    let suffix = variant.map { "-\($0)" } ?? ""
    let useFallback = !suffix.isEmpty
    let assets = (
      before: loadCSS(named: "\(filePrefix)-before\(suffix)")
        ?? (useFallback ? loadCSS(named: "\(filePrefix)-before") : nil)
          ?? "",
      defaultCSS: loadCSS(named: "\(filePrefix)-default\(suffix)")
        ?? (useFallback ? loadCSS(named: "\(filePrefix)-default") : nil)
          ?? "",
      after: loadCSS(named: "\(filePrefix)-after\(suffix)")
        ?? (useFallback ? loadCSS(named: "\(filePrefix)-after") : nil)
        ?? ""
    )
    cache[cacheKey] = assets
    return assets
  }

  static func resolveVariantSubdirectory(
    language: String?,
    readingProgression: WebPubReadingProgression?
  ) -> String? {
    let languageCode = normalizedLanguageCode(language)
    let isRTL = readingProgression == .rtl
    let isCJK = ["zh", "ja", "ko"].contains(languageCode ?? "")
    let isRTLLanguage = ["ar", "fa", "he"].contains(languageCode ?? "")

    if isRTL && isRTLLanguage {
      return "rtl"
    }

    if isCJK {
      return isRTL ? "cjk-vertical" : "cjk-horizontal"
    }

    return nil
  }

  private static func loadCSS(named: String) -> String? {
    if let url = Bundle.main.url(forResource: named, withExtension: "css", subdirectory: baseSubdirectory) {
      return try? String(contentsOf: url, encoding: .utf8)
    }
    if let url = Bundle.main.url(forResource: named, withExtension: "css") {
      return try? String(contentsOf: url, encoding: .utf8)
    }
    return nil
  }

  private static func normalizedLanguageCode(_ language: String?) -> String? {
    guard let language, !language.isEmpty else { return nil }
    let normalized =
      language
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    return
      normalized
      .split(whereSeparator: { $0 == "-" || $0 == "_" })
      .first
      .map(String.init)
  }
}
