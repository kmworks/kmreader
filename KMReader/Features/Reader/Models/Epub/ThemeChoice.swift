import SwiftUI

nonisolated enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
  case system
  case quiet
  case sepia
  case green

  var id: String { rawValue }

  func resolvedTheme(for colorScheme: ColorScheme?) -> ReaderTheme {
    let isDark = colorScheme == .dark
    switch self {
    case .system: return isDark ? .black : .white
    case .quiet: return isDark ? .darkQuiet : .lightQuiet
    case .sepia: return isDark ? .darkSepia : .lightSepia
    case .green: return isDark ? .darkGreen : .lightGreen
    }
  }
}
