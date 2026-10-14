import Foundation

enum MangaTranslationPhase: Equatable, Sendable {
  case idle
  case preparingModels
  case detecting
  case recognizing
  case translating
  case completed
  case noText
  case failed(MangaTranslationFailure)

  var isBusy: Bool {
    switch self {
    case .preparingModels, .detecting, .recognizing, .translating:
      return true
    default:
      return false
    }
  }

  var icon: String {
    switch self {
    case .idle, .completed, .noText:
      return AppIcon.mangaTranslation
    case .preparingModels:
      return "cpu"
    case .detecting:
      return "viewfinder"
    case .recognizing:
      return "text.viewfinder"
    case .translating:
      return AppIcon.mangaTranslation
    case .failed:
      return AppIcon.loadError
    }
  }

  var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }

  var title: String {
    switch self {
    case .idle:
      return String(localized: "manga.action.translatePage")
    case .preparingModels:
      return String(localized: "manga.action.preparingModels")
    case .detecting:
      return String(localized: "manga.action.detecting")
    case .recognizing:
      return String(localized: "manga.action.recognizing")
    case .translating:
      return String(localized: "manga.action.translating")
    case .completed:
      return String(localized: "manga.action.completed")
    case .noText:
      return MangaTranslationFailure.noText.description
    case .failed(let failure):
      return failure.description
    }
  }
}
