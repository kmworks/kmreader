import Foundation

struct MangaTranslationButtonState: Equatable, Sendable {
  enum Tint: Equatable, Sendable {
    case none
    case active
    case failure
  }

  let icon: String
  let isBusy: Bool
  let tint: Tint
  let isEnabled: Bool
  let accessibilityLabel: String
}
