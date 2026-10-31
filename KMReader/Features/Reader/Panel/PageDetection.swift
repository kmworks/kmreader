//
// PageDetection.swift
//
// One page's detection across all three model classes, as normalized [0,1] boxes: the panels
// plus the text and body boxes that the content-aware composition layer uses to frame panels,
// prune empties, and insert beats. Detector-specific suppression has already run; reading order
// and beat composition have not (that is PanelComposition's job). A provider that only finds
// panels leaves texts/bodies empty.
//

import Foundation

nonisolated struct PageDetection: Equatable, Sendable {
  /// Kept panel boxes (post-suppression, unordered — composition orders them).
  var panels: [PanelRect]
  /// Speech/caption boxes (text class), deduped, unordered.
  var texts: [PanelRect]
  /// Character/figure boxes (body class), deduped, unordered.
  var bodies: [PanelRect]

  static let empty = PageDetection(panels: [], texts: [], bodies: [])
}
