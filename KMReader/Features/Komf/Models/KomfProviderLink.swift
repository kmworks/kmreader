//
// KomfProviderLink.swift
//
//

import Foundation

/// A provider series reference recognized from a series/book web link, submittable
/// to komf identify as-is. Provider names follow komf's SCREAMING_SNAKE ids.
nonisolated struct KomfProviderLink: Equatable, Sendable, Identifiable {
  let provider: String
  let providerSeriesId: String
  let url: String

  var id: String { "\(provider):\(providerSeriesId)" }

  var displayName: String {
    switch provider {
    case "BANGUMI": return "Bangumi"
    case "EHENTAI": return "E-Hentai"
    case "ANILIST": return "AniList"
    case "MAL": return "MAL"
    case "MANGADEX": return "MangaDex"
    case "MANGA_UPDATES": return "MangaUpdates"
    default: return provider
    }
  }

  /// Deduped provider links found in the given web links, order preserved.
  static func parseAll(_ links: [WebLink]) -> [KomfProviderLink] {
    var seen = Set<String>()
    return links.compactMap(parse).filter { seen.insert($0.id).inserted }
  }

  private static func parse(_ link: WebLink) -> KomfProviderLink? {
    let url = link.url.lowercased()
    if (url.contains("bgm.tv") || url.contains("bangumi.tv")) && url.contains("/subject/"),
      let id = firstMatch(#"\/subject\/([^/?]+)"#, in: url)
    {
      return KomfProviderLink(provider: "BANGUMI", providerSeriesId: id, url: link.url)
    }
    if url.contains("e-hentai.org") || url.contains("exhentai.org"),
      let id = firstMatch(#"\/g\/([^/]+)\/([^/?]+)"#, in: url, group: 1),
      let token = firstMatch(#"\/g\/([^/]+)\/([^/?]+)"#, in: url, group: 2)
    {
      return KomfProviderLink(
        provider: "EHENTAI", providerSeriesId: "\(id);\(token)", url: link.url)
    }
    if url.contains("anilist.co"),
      let id = firstMatch(#"\/(?:anime|manga)\/(\d+)"#, in: url)
    {
      return KomfProviderLink(provider: "ANILIST", providerSeriesId: id, url: link.url)
    }
    if url.contains("myanimelist.net"),
      let id = firstMatch(#"\/(?:anime|manga)\/(\d+)"#, in: url)
    {
      return KomfProviderLink(provider: "MAL", providerSeriesId: id, url: link.url)
    }
    if url.contains("mangadex.org"),
      let id = firstMatch(#"\/title\/([^/?]+)"#, in: url)
    {
      return KomfProviderLink(provider: "MANGADEX", providerSeriesId: id, url: link.url)
    }
    if url.contains("mangaupdates.com"),
      let id = firstMatch(#"\/series\/([^/?]+)"#, in: url)
        ?? firstMatch(#"series\.html\?id=(\d+)"#, in: url)
    {
      return KomfProviderLink(provider: "MANGA_UPDATES", providerSeriesId: id, url: link.url)
    }
    return nil
  }

  private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: group), in: text)
    else { return nil }
    return String(text[range])
  }
}
