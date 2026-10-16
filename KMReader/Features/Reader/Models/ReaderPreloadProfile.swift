import Foundation

enum ReaderPreloadProfile: String, CaseIterable, Identifiable {
  case lowMemory
  case balanced
  case fastPageTurns

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .lowMemory:
      return String(localized: "Low Memory")
    case .balanced:
      return String(localized: "Balanced")
    case .fastPageTurns:
      return String(localized: "Fast Page Turns")
    }
  }

  var description: String {
    switch self {
    case .lowMemory:
      return String(
        localized: "Decode fewer nearby pages to reduce memory usage. Page turns may wait for loading more often.")
    case .balanced:
      return String(
        localized: "Use the default preloading window for a balance between memory usage and smooth page turns.")
    case .fastPageTurns:
      return String(
        localized: "Keep more nearby pages decoded for smoother page turns at the cost of higher memory usage.")
    }
  }

  var window: ReaderPreloadWindow {
    switch self {
    case .lowMemory:
      return .lowMemory
    case .balanced:
      return .balanced
    case .fastPageTurns:
      return .fastPageTurns
    }
  }
}
