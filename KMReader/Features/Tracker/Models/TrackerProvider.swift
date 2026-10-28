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

  func entryURL(trackId: String) -> URL? {
    switch self {
    case .anilist: return URL(string: "https://anilist.co/manga/\(trackId)")
    case .mal: return URL(string: "https://myanimelist.net/manga/\(trackId)")
    case .bangumi: return URL(string: "https://bgm.tv/subject/\(trackId)")
    case .mangabaka: return URL(string: "https://mangabaka.org/\(trackId)")
    }
  }
}
