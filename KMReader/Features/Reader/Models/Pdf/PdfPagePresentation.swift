import Foundation

enum PdfPagePresentation: String, CaseIterable, Hashable, Sendable {
  case auto = "auto"
  case singlePaged = "single-paged"
  case singleContinuous = "single-continuous"
  case dualContinuous = "dual-continuous"

  func resolved(for size: CGSize) -> PdfPagePresentation {
    guard self == .auto else { return self }
    guard size.width > 0, size.height > 0 else { return .singlePaged }
    return size.width > size.height ? .dualContinuous : .singlePaged
  }

  var resolvedPageLayout: PageLayout {
    switch self {
    case .auto:
      return .auto
    case .singlePaged, .singleContinuous:
      return .single
    case .dualContinuous:
      return .dual
    }
  }

  var resolvedContinuousScroll: Bool {
    switch self {
    case .auto, .singlePaged:
      return false
    case .singleContinuous, .dualContinuous:
      return true
    }
  }

  var displayName: String {
    switch self {
    case .auto:
      return String(localized: "Auto")
    case .singlePaged:
      return String(localized: "Single Page")
    case .singleContinuous:
      return String(localized: "Single Page Continuous")
    case .dualContinuous:
      return String(localized: "Dual Page Continuous")
    }
  }

  var detailText: String {
    switch self {
    case .auto:
      return String(localized: "Uses dual-page continuous mode in landscape and single-page paged mode in portrait.")
    case .singlePaged:
      return String(localized: "Uses the native page controller for discrete page turns.")
    case .singleContinuous:
      return String(localized: "Scrolls through one page at a time continuously.")
    case .dualContinuous:
      return String(localized: "Scrolls through two-page spreads continuously.")
    }
  }

  var icon: String {
    switch self {
    case .auto:
      return "sparkles"
    case .singlePaged:
      return "rectangle.portrait"
    case .singleContinuous:
      return "scroll"
    case .dualContinuous:
      return "rectangle.split.2x1"
    }
  }

  var supportsCoverSolo: Bool {
    self == .auto || self == .dualContinuous
  }
}
