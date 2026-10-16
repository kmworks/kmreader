//
// PdfOfflineRenderQuality.swift
//
//

import CoreGraphics
import Foundation

enum PdfOfflineRenderQuality: String, CaseIterable, Hashable, Sendable {
  case compact
  case balanced
  case high
  case ultra

  nonisolated var displayName: String {
    switch self {
    case .compact:
      return String(localized: "Compact (2048 px)")
    case .balanced:
      return String(localized: "Balanced (3072 px)")
    case .high:
      return String(localized: "High (4096 px)")
    case .ultra:
      return String(localized: "Ultra (5120 px)")
    }
  }

  nonisolated var detailText: String {
    switch self {
    case .compact:
      return String(localized: "Smallest offline files. Best for phones and limited storage.")
    case .balanced:
      return String(localized: "Smaller offline files with good quality on most phones.")
    case .high:
      return String(localized: "Sharper text and line art. Recommended for iPad and Mac.")
    case .ultra:
      return String(localized: "Largest offline files. Best for heavy zooming and large screens.")
    }
  }

  nonisolated var maxLongEdge: CGFloat {
    switch self {
    case .compact:
      return 2048
    case .balanced:
      return 3072
    case .high:
      return 4096
    case .ultra:
      return 5120
    }
  }
}
