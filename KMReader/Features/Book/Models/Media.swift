//
// Media.swift
//
//

import Foundation
import SwiftUI

nonisolated enum MediaProfile: String, Codable, Hashable, Sendable {
  case divina = "DIVINA"
  case pdf = "PDF"
  case epub = "EPUB"
  case unknown = ""
}

nonisolated enum MediaStatus: String, Codable, Hashable, Sendable {
  case ready = "READY"
  case unknown = "UNKNOWN"
  case error = "ERROR"
  case unsupported = "UNSUPPORTED"
  case outdated = "OUTDATED"

  var message: String {
    switch self {
    case .ready:
      return ""
    case .error:
      return String(localized: "Failed to load media")
    case .unsupported:
      return String(localized: "Media format is not supported")
    case .outdated:
      return String(localized: "Media is outdated")
    case .unknown:
      return String(localized: "Media status is unknown")
    }
  }

  var label: String {
    switch self {
    case .ready:
      return String(localized: "Ready")
    case .error:
      return String(localized: "Error")
    case .unsupported:
      return String(localized: "Unsupported")
    case .outdated:
      return String(localized: "Outdated")
    case .unknown:
      return String(localized: "Unknown")
    }
  }

  var icon: String {
    switch self {
    case .ready:
      return ""
    case .error:
      return AppIcon.loadError
    case .unsupported:
      return "doc.questionmark"
    case .outdated:
      return "clock.badge.exclamationmark"
    case .unknown:
      return "questionmark.circle"
    }
  }

  var color: Color {
    switch self {
    case .ready:
      return .blue
    case .error:
      return .red
    case .unsupported:
      return .orange
    case .outdated:
      return .yellow
    case .unknown:
      return .gray
    }
  }

  /// Detail-page status rows are caption-sized, where yellow is unreadable.
  var detailColor: Color {
    switch self {
    case .ready, .unknown:
      return .secondary
    case .error:
      return .red
    case .unsupported, .outdated:
      return .orange
    }
  }
}

nonisolated struct Media: Equatable, Hashable, Sendable {
  static let empty = Media(status: MediaStatus.unknown.rawValue, mediaType: "", pagesCount: 0)

  var status: String = MediaStatus.unknown.rawValue
  var mediaType: String = ""
  var pagesCount: Int = 0
  var comment: String?
  var mediaProfile: String?
  var epubDivinaCompatible: Bool?
  var epubIsKepub: Bool?

  var statusValue: MediaStatus {
    MediaStatus(rawValue: status) ?? .unknown
  }

  var mediaProfileValue: MediaProfile? {
    guard let mediaProfile else {
      return nil
    }
    return MediaProfile(rawValue: mediaProfile) ?? .unknown
  }

  var localizedComment: String? {
    KomgaErrorCodeFormatter.localizedMessage(for: comment)
  }

  init(
    status: String,
    mediaType: String,
    pagesCount: Int,
    comment: String? = nil,
    mediaProfile: String? = nil,
    epubDivinaCompatible: Bool? = nil,
    epubIsKepub: Bool? = nil
  ) {
    self.status = status
    self.mediaType = mediaType
    self.pagesCount = pagesCount
    self.comment = comment
    self.mediaProfile = mediaProfile
    self.epubDivinaCompatible = epubDivinaCompatible
    self.epubIsKepub = epubIsKepub
  }

  init(
    status: MediaStatus,
    mediaType: String,
    pagesCount: Int,
    comment: String? = nil,
    mediaProfile: MediaProfile? = nil,
    epubDivinaCompatible: Bool? = nil,
    epubIsKepub: Bool? = nil
  ) {
    self.init(
      status: status.rawValue,
      mediaType: mediaType,
      pagesCount: pagesCount,
      comment: comment,
      mediaProfile: mediaProfile?.rawValue,
      epubDivinaCompatible: epubDivinaCompatible,
      epubIsKepub: epubIsKepub
    )
  }
}

nonisolated extension Media: Codable {
  enum CodingKeys: String, CodingKey {
    case status
    case mediaType
    case pagesCount
    case comment
    case mediaProfile
    case epubDivinaCompatible
    case epubIsKepub
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? MediaStatus.unknown.rawValue
    mediaType = try container.decode(String.self, forKey: .mediaType)
    pagesCount = try container.decode(Int.self, forKey: .pagesCount)
    comment = try container.decodeIfPresent(String.self, forKey: .comment)
    mediaProfile = try container.decodeIfPresent(String.self, forKey: .mediaProfile)
    epubDivinaCompatible = try container.decodeIfPresent(Bool.self, forKey: .epubDivinaCompatible)
    epubIsKepub = try container.decodeIfPresent(Bool.self, forKey: .epubIsKepub)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(status, forKey: .status)
    try container.encode(mediaType, forKey: .mediaType)
    try container.encode(pagesCount, forKey: .pagesCount)
    try container.encodeIfPresent(comment, forKey: .comment)
    try container.encodeIfPresent(mediaProfile, forKey: .mediaProfile)
    try container.encodeIfPresent(epubDivinaCompatible, forKey: .epubDivinaCompatible)
    try container.encodeIfPresent(epubIsKepub, forKey: .epubIsKepub)
  }
}
