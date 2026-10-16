import SwiftUI

nonisolated enum ReaderTheme: String, CaseIterable, Sendable {
  case white
  case black
  case lightQuiet
  case darkQuiet
  case lightSepia
  case darkSepia
  case lightGreen
  case darkGreen

  var backgroundColorHex: String {
    switch self {
    case .white: return "#FFFFFF"
    case .black: return "#000000"
    case .lightQuiet: return "#FAFAFA"
    case .darkQuiet: return "#1E1E1E"
    case .lightSepia: return "#F4ECD8"
    case .darkSepia: return "#382E25"
    case .lightGreen: return "#C7EDCC"
    case .darkGreen: return "#1B261B"
    }
  }

  var textColorHex: String {
    switch self {
    case .white: return "#000000"
    case .black: return "#E0E0E0"
    case .lightQuiet: return "#111111"
    case .darkQuiet: return "#BDBDBD"
    case .lightSepia: return "#5C4A37"
    case .darkSepia: return "#E3D5C1"
    case .lightGreen: return "#1A3A1F"
    case .darkGreen: return "#D1E0D1"
    }
  }

  var isDark: Bool {
    switch self {
    case .black, .darkQuiet, .darkSepia, .darkGreen:
      return true
    default:
      return false
    }
  }

  var isSepia: Bool {
    switch self {
    case .lightSepia, .darkSepia, .lightGreen, .darkGreen:
      return true
    default:
      return false
    }
  }

  @MainActor
  var backgroundColor: Color {
    Color(hex: backgroundColorHex) ?? .black
  }

  @MainActor
  var textColor: Color {
    Color(hex: textColorHex) ?? .white
  }
}
