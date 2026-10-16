//
// WebtoonConstants.swift
//
//

import Foundation

enum WebtoonConstants {
  static let initialScrollDelay: TimeInterval = 0.3
  static let initialScrollRetryDelay: TimeInterval = 0.15
  static let initialScrollMaxRetries: Int = 8
  static let layoutReadyDelay: TimeInterval = 0.2
  static let bottomThreshold: CGFloat = 60
  static let topContentPadding: CGFloat = 120
  static let footerHeight: CGFloat = 480
  static let measuringPlaceholderHeight: CGFloat = 120
  static let scrollAnimationDuration: TimeInterval = 0.3
  static let clickDebounceAfterScroll: TimeInterval = 0.25
  static let preheatRadius: Int = 2
  static let offsetEpsilon: CGFloat = 0.5
  static let postScrollReloadDelay: TimeInterval = 0.12
  static let postScrollCleanupDelay: TimeInterval = 0.2
}
