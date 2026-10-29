//
// TrackerProvider.swift
//

import Foundation

nonisolated enum TrackerProvider: String, CaseIterable, Codable, Sendable {
  case anilist
  case mal
  case bangumi
  case mangabaka

  var displayName: String {
    switch self {
    case .anilist: return "AniList"
    case .mal: return "MyAnimeList"
    case .bangumi: return "Bangumi"
    case .mangabaka: return "MangaBaka"
    }
  }

  var imageName: String {
    switch self {
    case .anilist: return "TrackerAniList"
    case .mal: return "TrackerMyAnimeList"
    case .bangumi: return "TrackerBangumi"
    case .mangabaka: return "TrackerMangaBaka"
    }
  }

  func entryURL(trackId: String) -> URL? {
    switch self {
    case .anilist: return URL(string: "https://anilist.co/manga/\(trackId)")
    case .mal: return URL(string: "https://myanimelist.net/manga/\(trackId)")
    case .bangumi: return URL(string: "https://bgm.tv/subject/\(trackId)")
    case .mangabaka: return URL(string: "https://mangabaka.org/\(trackId)")
    }
  }

  /// Entry id from a platform entry page URL such as a series metadata link.
  func entryId(from url: URL) -> String? {
    guard url.scheme == "http" || url.scheme == "https", let host = url.host?.lowercased() else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }
    switch self {
    case .anilist:
      guard Self.host(host, matches: "anilist.co") else { return nil }
      return Self.numericId(components, after: "manga")
    case .mal:
      guard Self.host(host, matches: "myanimelist.net") else { return nil }
      return Self.numericId(components, after: "manga")
    case .bangumi:
      guard Self.host(host, matches: "bgm.tv") || Self.host(host, matches: "bangumi.tv") else { return nil }
      return Self.numericId(components, after: "subject")
    case .mangabaka:
      guard Self.host(host, matches: "mangabaka.org") else { return nil }
      if components.first == "series" {
        return Self.numericId(components, after: "series")
      }
      return components.first.flatMap { Self.isDigits($0) ? $0 : nil }
    }
  }

  /// Canonical entry URLs found in series metadata links, fed to the search endpoint which resolves them directly.
  static func entryURLs(in links: [WebLink]) -> [TrackerProvider: URL] {
    var result: [TrackerProvider: URL] = [:]
    for link in links {
      guard let url = URL(string: link.url.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
      for provider in allCases where result[provider] == nil {
        if let id = provider.entryId(from: url), let entryURL = provider.entryURL(trackId: id) {
          result[provider] = entryURL
        }
      }
    }
    return result
  }

  private static func host(_ host: String, matches domain: String) -> Bool {
    host == domain || host.hasSuffix("." + domain)
  }

  private static func numericId(_ components: [String], after prefix: String) -> String? {
    guard components.count >= 2, components[0] == prefix, isDigits(components[1]) else { return nil }
    return components[1]
  }

  private static func isDigits(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
  }
}
