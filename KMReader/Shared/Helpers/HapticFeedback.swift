//
//  HapticFeedback.swift
//
//

#if os(iOS)
  import UIKit

  /// Shared haptic entry points so feedback style and prepare timing stay consistent.
  /// Haptics fire only on discrete boundary crossings, never on continuous motion.
  enum HapticFeedback {
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()

    static func light() {
      impactLight.impactOccurred()
    }

    static func medium() {
      impactMedium.impactOccurred()
    }

    static func selectionChanged() {
      selection.selectionChanged()
    }

    /// Warm up the generators on touch-down so the first trigger has no latency.
    static func prepare() {
      impactLight.prepare()
      impactMedium.prepare()
      selection.prepare()
    }
  }
#else
  enum HapticFeedback {
    static func light() {}
    static func medium() {}
    static func selectionChanged() {}
    static func prepare() {}
  }
#endif
