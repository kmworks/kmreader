import Foundation

nonisolated enum MangaTranslationTextDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case auto
  case horizontal
  case vertical

  // The auto gate keeps vertical layout to languages that typeset
  // vertically; Latin-script targets always stay horizontal.
  func usesVerticalLayout(for region: MangaTextRegion, targetLanguage: String) -> Bool {
    switch self {
    case .vertical:
      return true
    case .horizontal:
      return false
    case .auto:
      guard MangaTranslationLanguage.supportsVerticalLayout(targetLanguage) else { return false }
      let orientation =
        region.orientation == .unknown
        ? MangaTextOrientation.infer(from: region.box) : region.orientation
      return orientation == .vertical
    }
  }
}
