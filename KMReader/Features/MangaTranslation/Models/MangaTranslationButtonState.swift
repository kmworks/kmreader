import Foundation

struct MangaTranslationButtonState: Equatable, Sendable {
  enum Style: Equatable, Sendable {
    case normal
    case inverted
    case failure
  }

  let icon: String
  let isBusy: Bool
  let style: Style
  let isEnabled: Bool
  let accessibilityLabel: String
}
