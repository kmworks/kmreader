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
}
