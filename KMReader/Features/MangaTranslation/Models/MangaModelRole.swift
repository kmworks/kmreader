import Foundation

nonisolated enum MangaModelRole: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
  case detector
  case recognizer

  var id: String { rawValue }

  // Role names double as manifest component names.
  var componentName: String { rawValue }

  var selectionStorageKey: String {
    "\(ModelPurpose.mangaOCR.rawValue).\(rawValue)"
  }

  var title: String {
    switch self {
    case .detector: return String(localized: "Detection Model")
    case .recognizer: return String(localized: "Recognition Model")
    }
  }

  static func capabilityTitle(for archive: ModelArchive) -> String {
    allCases.filter { archive.components[$0.componentName] != nil }
      .map(\.title)
      .joined(separator: " + ")
  }
}
