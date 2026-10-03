//
// KomfIdentifyRequest.swift
//
//

import Foundation

nonisolated struct KomfIdentifyRequest: Sendable {
  let libraryId: String?
  let seriesId: String
  let provider: String
  let providerSeriesId: String

  var jsonObject: [String: Any] {
    var dict: [String: Any] = [
      "seriesId": seriesId,
      "provider": provider,
      "providerSeriesId": providerSeriesId,
    ]
    if let libraryId {
      dict["libraryId"] = libraryId
    }
    return dict
  }
}
