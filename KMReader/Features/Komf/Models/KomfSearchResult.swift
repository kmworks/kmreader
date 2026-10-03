//
// KomfSearchResult.swift
//
//

import Foundation

nonisolated struct KomfSearchResult: Codable, Equatable, Sendable, Identifiable {
  let url: String?
  let imageUrl: String?
  let title: String
  let provider: String
  let resultId: String
  let mediaType: String?
  let language: String?

  var id: String { "\(provider):\(resultId)" }

  var metaText: String {
    [mediaType, language].compactMap { $0 }.joined(separator: " · ")
  }
}
