import Foundation

struct MangaTranslationButtonState: Equatable, Sendable {
  enum Style: Equatable, Sendable {
    case normal
    /// The page's translation overlay is showing; the button inverts to
    /// solid black so it reads as active over the overlay.
    case overlayVisible
    case failure
  }

  let icon: String
  let isBusy: Bool
  let style: Style
  let isEnabled: Bool
  let accessibilityLabel: String
}
